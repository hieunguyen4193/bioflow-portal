process AMBIENT_DECONTAMINATION {
    tag "${sample} / ${method}"
    publishDir "${params.outdir}/s2_ambient",               mode: "copy"

    input:
    tuple val(sample), path(seurat_rds)
    val  method

    output:
    tuple val(sample), path("*_s2.rds"), emit: seurat_rds
    path "*.png",                        emit: plots, optional: true

    script:
    """
    cat > run_ambient.R << 'REOF'
suppressPackageStartupMessages({
  library(Seurat)
  library(ggplot2)
  library(optparse)
})

option_list <- list(
  make_option("--rds",    type = "character"),
  make_option("--method", type = "character", default = "decontX"),
  make_option("--sample", type = "character", default = "sample")
)
opt <- parse_args(OptionParser(option_list = option_list))

s.obj <- readRDS(opt\$rds)

# ── Ambient RNA correction function ───────────────────────────────────────
s2_ambient_RNA_correction <- function(s.obj, chosen.method, PROJECT) {

  if (chosen.method == "decontX") {
    suppressPackageStartupMessages({
      library(celda)
      library(SingleCellExperiment)
    })

    if (length(unique(s.obj\$name)) >= 2) {
      s.obj <- JoinLayers(s.obj)
    }

    s.obj.sce <- as.SingleCellExperiment(s.obj)

    s.obj.decontX <- decontX(s.obj.sce, batch = s.obj\$name)

    s.obj[["decontX"]] <- CreateAssayObject(
      counts = s.obj.decontX@assays@data\$decontXcounts
    )
    s.obj <- AddMetaData(s.obj,
      metadata = s.obj.decontX\$decontX_contamination,
      col.name = "AmbientRNA")
    s.obj <- AddMetaData(s.obj,
      metadata = s.obj.decontX\$decontX_clusters,
      col.name = "decontX_clusters")

    ambient.cluster.RNA   <- list()
    ambient.contamination <- list()

    for (dim.name in reducedDimNames(s.obj.decontX)) {
      umap <- reducedDim(s.obj.decontX, dim.name)
      p <- plotDimReduceCluster(
        x    = s.obj\$decontX_clusters,
        dim1 = umap[, 1],
        dim2 = umap[, 2]
      ) + ggtitle(sprintf("Dim. reduce cluster (%s)", dim.name))
      ambient.cluster.RNA[[paste0(dim.name, ".plot")]] <- p
      ggsave(sprintf("ambient_cluster_%s.png", dim.name), p, width = 8, height = 6, dpi = 150)
    }

    for (sample.name in unique(s.obj\$name)) {
      p <- plotDecontXContamination(s.obj.decontX, batch = sample.name) +
        ggtitle(sprintf("Contamination: %s", sample.name))
      ambient.contamination[[sample.name]] <- p
      ggsave(sprintf("ambient_contamination_%s.png", sample.name), p, width = 8, height = 6, dpi = 150)
    }

    s.obj@misc\$ambient.cluster.RNA.plot   <- ambient.cluster.RNA
    s.obj@misc\$ambient.contamination.plot <- ambient.contamination

  } else if (chosen.method == "SoupX") {
    stop("SoupX support is not yet implemented.")

  } else {
    stop("chosen.method must be 'decontX' or 'SoupX'. Got: ", chosen.method)
  }

  return(s.obj)
}

s.obj <- s2_ambient_RNA_correction(s.obj,
  chosen.method = opt\$method,
  PROJECT       = opt\$sample)

out_rds <- paste0(opt\$sample, "_s2.rds")
saveRDS(s.obj, out_rds)
message("Step 2 done. Saved: ", out_rds)
REOF

    Rscript run_ambient.R \\
        --rds    ${seurat_rds} \\
        --method "${method}" \\
        --sample "${sample}"
    """
}
