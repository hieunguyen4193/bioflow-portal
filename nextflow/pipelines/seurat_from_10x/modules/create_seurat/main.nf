process CREATE_SEURAT {
    tag "${sample}"
    publishDir "${params.outdir}/s1_seurat",               mode: "copy"
    publishDir "${params.outdir}/intermediates/s1_seurat", mode: "copy", pattern: "*_s1.rds"

    input:
    tuple val(sample), path(barcodes), path(features), path(matrix)
    val  min_cells
    val  min_features
    val  max_features
    val  max_mt_pct
    val  remove_tcr_genes

    output:
    tuple val(sample), path("*_s1.rds"), emit: seurat_rds
    path "*.png",                        emit: plots
    path "qc_stats.csv",                 emit: qc_table

    script:
    """
    # Build a Read10X-compatible directory from staged files
    mkdir -p tenx_input
    ln -sf "\$(realpath ${barcodes})" tenx_input/barcodes.tsv.gz
    ln -sf "\$(realpath ${features})" tenx_input/features.tsv.gz
    ln -sf "\$(realpath ${matrix})"   tenx_input/matrix.mtx.gz

    cat > run_create_seurat.R << 'REOF'
suppressPackageStartupMessages({
  library(Seurat)
  library(ggplot2)
  library(Matrix)
  library(optparse)
})

option_list <- list(
  make_option("--tenx_dir",         type = "character"),
  make_option("--sample",           type = "character", default = "sample"),
  make_option("--min_cells",        type = "character", default = "3"),
  make_option("--min_features",     type = "character", default = "200"),
  make_option("--max_features",     type = "character", default = "5000"),
  make_option("--max_mt_pct",       type = "character", default = "20"),
  make_option("--remove_TCR_genes", type = "character", default = "false")
)
opt <- parse_args(OptionParser(option_list = option_list))

min_cells    <- as.integer(opt\$min_cells)
min_features <- as.integer(opt\$min_features)
max_features <- as.integer(opt\$max_features)
max_mt_pct   <- as.numeric(opt\$max_mt_pct)
remove_tcr   <- tolower(opt\$remove_TCR_genes) == "true"

# ── Load data ──────────────────────────────────────────────────────────────
input.data <- Read10X(data.dir = opt\$tenx_dir)

# ── Detect CITE-seq ────────────────────────────────────────────────────────
is_multimodal <- is.list(input.data) && length(input.data) >= 2
if (is_multimodal) {
  message("CITE-seq detected: ", paste(names(input.data), collapse = ", "))
  count.data <- input.data[["Gene Expression"]]
  count.adt  <- input.data[[names(input.data)[[2]]]]
} else {
  message("RNA-only data detected.")
  count.data <- input.data
}

# ── Remove TCR genes ───────────────────────────────────────────────────────
if (remove_tcr) {
  keep <- !grepl("^TR[ABGD][VDJ]", rownames(count.data))
  message("Removing ", sum(!keep), " TCR genes.")
  count.data <- count.data[keep, ]
}

# ── Create Seurat object ───────────────────────────────────────────────────
seurat <- CreateSeuratObject(
  counts       = count.data,
  project      = opt\$sample,
  min.cells    = min_cells,
  min.features = min_features
)
seurat\$name <- opt\$sample

# ── Add ADT assay ──────────────────────────────────────────────────────────
if (is_multimodal) {
  shared_cells <- intersect(colnames(seurat), colnames(count.adt))
  seurat <- seurat[, shared_cells]
  seurat[["ADT"]] <- CreateAssay5Object(counts = count.adt[, shared_cells])
  message("ADT assay added: ", nrow(count.adt), " markers.")
}

# ── QC metrics ─────────────────────────────────────────────────────────────
seurat[["percent.mt"]] <- PercentageFeatureSet(seurat, pattern = "^MT-|^mt-")

p_pre <- VlnPlot(seurat,
  features = c("nFeature_RNA", "nCount_RNA", "percent.mt"),
  ncol = 3, pt.size = 0.1)
ggsave("qc_violin_prefilter.png", p_pre, width = 12, height = 5, dpi = 150)

p_scatter <- FeatureScatter(seurat, feature1 = "nCount_RNA", feature2 = "nFeature_RNA")
ggsave("qc_scatter.png", p_scatter, width = 6, height = 5, dpi = 150)

# ── Filter cells ───────────────────────────────────────────────────────────
cells_before <- ncol(seurat)
seurat <- subset(seurat,
  subset = nFeature_RNA > min_features &
           nFeature_RNA < max_features &
           percent.mt   < max_mt_pct)

p_post <- VlnPlot(seurat,
  features = c("nFeature_RNA", "nCount_RNA", "percent.mt"),
  ncol = 3, pt.size = 0.1)
ggsave("qc_violin_postfilter.png", p_post, width = 12, height = 5, dpi = 150)

# ── QC summary ─────────────────────────────────────────────────────────────
write.csv(data.frame(
  sample          = opt\$sample,
  multimodal      = is_multimodal,
  cells_raw       = cells_before,
  cells_filtered  = ncol(seurat),
  median_features = median(seurat\$nFeature_RNA),
  median_counts   = median(seurat\$nCount_RNA),
  median_pct_mt   = median(seurat\$percent.mt)
), "qc_stats.csv", row.names = FALSE)

saveRDS(seurat, paste0(opt\$sample, "_s1.rds"))
message("Step 1 done. Cells retained: ", ncol(seurat), " / ", cells_before)
REOF

    Rscript run_create_seurat.R \\
        --tenx_dir         tenx_input \\
        --sample           "${sample}" \\
        --min_cells        "${min_cells ?: 3}" \\
        --min_features     "${min_features ?: 200}" \\
        --max_features     "${max_features ?: 5000}" \\
        --max_mt_pct       "${max_mt_pct ?: 20}" \\
        --remove_TCR_genes "${remove_tcr_genes ?: false}"
    """
}
