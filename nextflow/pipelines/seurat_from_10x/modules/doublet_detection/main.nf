process DOUBLET_DETECTION {
    tag "${sample}"
    publishDir "${params.outdir}/s4_doublet",               mode: "copy"
    publishDir "${params.outdir}/intermediates/s4_doublet", mode: "copy", pattern: "*_s4.rds"

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
  make_option("--remove_doublet",  type = "logical",   default = FALSE)
)
opt <- parse_args(OptionParser(option_list = option_list))

s.obj <- readRDS(opt\$rds)

# ── Doublet detection function ─────────────────────────────────────────────
s4.DoubletDetection <- function(s.obj, path.to.10X.doublet.estimation,
                                remove_doublet = FALSE, PROJECT) {

  number_of_cells <- table(s.obj\$name)
  estimation.10X  <- read.csv(path.to.10X.doublet.estimation)

  # Interpolate doublet rate from 10X Genomics estimates
  model.recovered <- approxfun(
    x    = estimation.10X\$CellsRecovered,
    y    = estimation.10X\$MultipletRate / 100,  # convert % to proportion
    rule = 2
  )
  doublet_formation_rate        <- model.recovered(number_of_cells)
  names(doublet_formation_rate) <- names(number_of_cells)
  message("Doublet rates: ", paste(sprintf("%s=%.3f", names(doublet_formation_rate),
                                           doublet_formation_rate), collapse = ", "))

  # Split, preprocess, run UMAP per sample
  splitted.s.obj <- SplitObject(s.obj, split.by = "name")
  splitted.s.obj <- lapply(splitted.s.obj, function(x) {
    x <- NormalizeData(x)
    x <- FindVariableFeatures(x, selection.method = "vst", nfeatures = 2000)
    x <- ScaleData(x)
    x <- RunPCA(x)
    x <- RunUMAP(x, dims = 1:20)
    return(x)
  })

  # Parameter sweep to find optimal pK per sample
  sweep.res.list <- lapply(splitted.s.obj, paramSweep,  PCs = 1:20, sct = FALSE)
  sweep.stats    <- lapply(sweep.res.list, summarizeSweep, GT = FALSE)
  bcmvn          <- lapply(sweep.stats,   find.pK)

  # Helper: run DoubletFinder on one sample
  run.Doublet.Detection <- function(s.obj.single, doublet_formation_rate, pN = 0.25) {
    obj.name <- unique(s.obj.single\$name)

    # Pick pK with highest BCmvn score
    bcmvn.df <- bcmvn[[obj.name]]
    pK.opt   <- as.numeric(as.character(bcmvn.df\$pK[which.max(bcmvn.df\$BCmetric)]))
    message(sprintf("Sample %s: optimal pK = %.4f", obj.name, pK.opt))

    nExp_poi <- round(doublet_formation_rate[[obj.name]] * ncol(s.obj.single))
    tmp      <- doubletFinder(s.obj.single, PCs = 1:10, pN = pN,
                              pK = pK.opt, nExp = nExp_poi,
                              reuse.pANN = FALSE, sct = FALSE)

    # Standardise the classification column name
    df_col <- grep("^DF.classifications", colnames(tmp@meta.data), value = TRUE)
    tmp[["classifications"]] <- factor(tmp@meta.data[[df_col]],
                                       levels = c("Singlet", "Doublet"))
    return(tmp)
  }

  s.obj.list <- lapply(splitted.s.obj, run.Doublet.Detection,
                       doublet_formation_rate = doublet_formation_rate)

  # Collect classifications across all samples
  classifications <- c()
  cells           <- c()
  for (i in seq_along(s.obj.list)) {
    cells           <- c(cells,           names(s.obj.list[[i]]\$classifications))
    classifications <- c(classifications, as.character(s.obj.list[[i]]\$classifications))
  }
  classifications        <- factor(classifications, levels = c("Singlet", "Doublet"))
  names(classifications) <- cells

  s.obj <- AddMetaData(s.obj, classifications, col.name = "Doublet_classifications")

  # UMAP coloured by doublet status (per sample)
  for (sample.name in names(splitted.s.obj)) {
    p <- DimPlot(s.obj.list[[sample.name]], group.by = "classifications",
                 cols = c("Singlet" = "#2166AC", "Doublet" = "#D6604D")) +
         ggtitle(sprintf("Doublets: %s", sample.name))
    ggsave(sprintf("doublet_umap_%s.png", sample.name), p, width = 7, height = 6, dpi = 150)
  }

  if (isTRUE(remove_doublet)) {
    before <- ncol(s.obj)
    s.obj  <- subset(s.obj, Doublet_classifications == "Singlet")
    message(sprintf("Removed %d doublets (%d → %d cells)",
                    before - ncol(s.obj), before, ncol(s.obj)))
  }

  return(s.obj)
}

s.obj <- s4.DoubletDetection(
  s.obj,
  path.to.10X.doublet.estimation = opt\$doublet_csv,
  remove_doublet                 = opt\$remove_doublet,
  PROJECT                        = opt\$sample
)

# ── Summary table ──────────────────────────────────────────────────────────
doublet_tbl <- table(s.obj\$name, s.obj\$Doublet_classifications)
summary_df  <- as.data.frame.matrix(doublet_tbl)
summary_df\$sample  <- rownames(summary_df)
summary_df\$removed <- isTRUE(opt\$remove_doublet)
write.csv(summary_df, "doublet_summary.csv", row.names = FALSE)

saveRDS(s.obj, paste0(opt\$sample, "_s4.rds"))
message("Step 4 done.")
REOF

    Rscript run_doublet.R \\
        --rds            ${seurat_rds} \\
        --sample         "${sample}" \\
        --doublet_csv    ${doublet_csv} \\
        --remove_doublet ${remove_doublet}
    """
}
