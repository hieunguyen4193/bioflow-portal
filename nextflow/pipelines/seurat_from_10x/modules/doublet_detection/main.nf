process DOUBLET_DETECTION {
    tag "${sample}"
    memory { 16.GB * task.attempt }
    maxRetries 2
    publishDir "${params.outdir}/s4_doublet",               mode: "copy"

    input:
    tuple val(sample), path(seurat_rds)
    path  doublet_csv
    val   remove_doublet

    output:
    tuple val(sample), path("*_s4.rds"), emit: seurat_rds
    path  "doublet_summary.csv",         emit: summary
    path  "*.png",                       emit: plots, optional: true

    script:
    """
    cat > run_doublet.R << 'REOF'
suppressPackageStartupMessages({
  library(Seurat)
  library(DoubletFinder)
  library(ggplot2)
  library(optparse)
})

option_list <- list(
  make_option("--rds",             type = "character"),
  make_option("--sample",          type = "character", default = "sample"),
  make_option("--doublet_csv",     type = "character"),
  make_option("--remove_doublet",  type = "character", default = "false")
)
opt <- parse_args(OptionParser(option_list = option_list))

remove_doublet <- tolower(opt\$remove_doublet) == "true"

s.obj <- readRDS(opt\$rds)

s4.DoubletDetection <- function(s.obj, path.to.10X.doublet.estimation,
                                remove_doublet = FALSE, PROJECT) {

  number_of_cells <- table(s.obj\$name)
  estimation.10X  <- read.csv(path.to.10X.doublet.estimation)

  model.recovered <- approxfun(
    x    = estimation.10X\$CellsRecovered,
    y    = estimation.10X\$MultipletRate / 100,
    rule = 2
  )
  doublet_formation_rate        <- model.recovered(as.numeric(number_of_cells))
  names(doublet_formation_rate) <- names(number_of_cells)
  message("Doublet rates: ", paste(sprintf("%s=%.3f", names(doublet_formation_rate),
                                           doublet_formation_rate), collapse = ", "))

  splitted.s.obj <- SplitObject(s.obj, split.by = "name")
  splitted.s.obj <- lapply(splitted.s.obj, function(x) {
    x <- JoinLayers(x)                  # flatten Seurat v5 split layers before DoubletFinder
    x <- NormalizeData(x)
    x <- FindVariableFeatures(x, selection.method = "vst", nfeatures = 2000)
    hvg <- VariableFeatures(x)
    x <- ScaleData(x, features = hvg)
    x <- RunPCA(x, features = hvg)
    x <- RunUMAP(x, dims = 1:20)
    # Coerce to plain matrix — fixes Seurat v5 / DoubletFinder incompatibility
    x@reductions[["pca"]]@cell.embeddings  <- as.matrix(x@reductions[["pca"]]@cell.embeddings)
    x@reductions[["umap"]]@cell.embeddings <- as.matrix(x@reductions[["umap"]]@cell.embeddings)
    return(x)
  })

  pK_per_sample <- tryCatch({
    sweep.res.list <- lapply(splitted.s.obj, paramSweep, PCs = 1:20, sct = FALSE)
    sweep.stats    <- lapply(sweep.res.list, summarizeSweep, GT = FALSE)
    pk <- sapply(names(sweep.stats), function(nm) {
      stats    <- sweep.stats[[nm]]
      bcmetric <- as.numeric(as.character(stats\$BCmetric))
      pk_vals  <- as.numeric(as.character(stats\$pK))
      best     <- pk_vals[which.max(bcmetric)]
      if (length(best) == 0 || is.na(best)) 0.09 else best
    })
    message("Auto pK per sample: ",
            paste(sprintf("%s=%.4f", names(pk), pk), collapse = ", "))
    pk
  }, error = function(e) {
    message("paramSweep failed (", conditionMessage(e), ") — using default pK=0.09")
    setNames(rep(0.09, length(splitted.s.obj)), names(splitted.s.obj))
  })

  run.Doublet.Detection <- function(s.obj.single, doublet_formation_rate, pN = 0.25) {
    obj.name  <- unique(s.obj.single\$name)
    pK.opt    <- pK_per_sample[[obj.name]]
    nExp_poi  <- round(doublet_formation_rate[[obj.name]] * ncol(s.obj.single))

    tmp <- doubletFinder(s.obj.single, PCs = 1:10, pN = pN,
                         pK = pK.opt, nExp = nExp_poi,
                         reuse.pANN = NULL, sct = FALSE)

    df_col <- grep("^DF.classifications", colnames(tmp@meta.data), value = TRUE)
    tmp[["classifications"]] <- factor(tmp@meta.data[[df_col]],
                                       levels = c("Singlet", "Doublet"))
    return(tmp)
  }

  s.obj.list <- lapply(splitted.s.obj, run.Doublet.Detection,
                       doublet_formation_rate = doublet_formation_rate)

  classifications <- c()
  cells           <- c()
  for (i in seq_along(s.obj.list)) {
    cells           <- c(cells,           names(s.obj.list[[i]]\$classifications))
    classifications <- c(classifications, as.character(s.obj.list[[i]]\$classifications))
  }
  classifications        <- factor(classifications, levels = c("Singlet", "Doublet"))
  names(classifications) <- cells

  s.obj <- AddMetaData(s.obj, classifications, col.name = "Doublet_classifications")

  for (sample.name in names(splitted.s.obj)) {
    p <- DimPlot(s.obj.list[[sample.name]], group.by = "classifications",
                 cols = c("Singlet" = "#2166AC", "Doublet" = "#D6604D")) +
         ggtitle(sprintf("Doublets: %s", sample.name))
    ggsave(sprintf("doublet_umap_%s.png", sample.name), p, width = 7, height = 6, dpi = 150)
  }

  if (remove_doublet) {
    before <- ncol(s.obj)
    s.obj  <- subset(s.obj, Doublet_classifications == "Singlet")
    message(sprintf("Removed %d doublets (%d -> %d cells)",
                    before - ncol(s.obj), before, ncol(s.obj)))
  }

  return(s.obj)
}

s.obj <- s4.DoubletDetection(
  s.obj,
  path.to.10X.doublet.estimation = opt\$doublet_csv,
  remove_doublet                 = remove_doublet,
  PROJECT                        = opt\$sample
)

doublet_tbl <- table(s.obj\$name, s.obj\$Doublet_classifications)
summary_df  <- as.data.frame.matrix(doublet_tbl)
summary_df\$sample  <- rownames(summary_df)
summary_df\$removed <- remove_doublet
write.csv(summary_df, "doublet_summary.csv", row.names = FALSE)

saveRDS(s.obj, paste0(opt\$sample, "_s4.rds"))
message("Step 4 done.")
REOF

    Rscript run_doublet.R \\
        --rds            "${seurat_rds}" \\
        --sample         "${sample}" \\
        --doublet_csv    "${doublet_csv}" \\
        --remove_doublet "${remove_doublet ?: false}"
    """
}
