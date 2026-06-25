process FILTER_CELLS {
    tag "${sample}"
    publishDir "${params.outdir}/s3_filter",               mode: "copy"

    input:
    tuple val(sample), path(seurat_rds)
    val  nFeatureRNA_floor
    val  nFeatureRNA_ceiling
    val  nCountRNA_floor
    val  nCountRNA_ceiling
    val  pct_mito_floor
    val  pct_mito_ceiling
    val  pct_ribo_floor
    val  pct_ribo_ceiling
    val  ambientRNA_thres
    val  log10GenesPerUMI_thres

    output:
    tuple val(sample), path("*_s3.rds"), emit: seurat_rds
    path "qc_filter_stats.csv",          emit: qc_table
    path "*.png",                        emit: plots, optional: true

    script:
    def args = [
        "--nFeatureRNA_floor":       nFeatureRNA_floor,
        "--nFeatureRNA_ceiling":     nFeatureRNA_ceiling,
        "--nCountRNA_floor":         nCountRNA_floor,
        "--nCountRNA_ceiling":       nCountRNA_ceiling,
        "--pct_mito_floor":          pct_mito_floor,
        "--pct_mito_ceiling":        pct_mito_ceiling,
        "--pct_ribo_floor":          pct_ribo_floor,
        "--pct_ribo_ceiling":        pct_ribo_ceiling,
        "--ambientRNA_thres":        ambientRNA_thres,
        "--log10GenesPerUMI_thres":  log10GenesPerUMI_thres,
    ].findAll { k, v -> v != "null" && v != "" }
     .collect { k, v -> "$k $v" }
     .join(" \\\n        ")

    """
    cat > run_filter.R << 'REOF'
suppressPackageStartupMessages({
  library(Seurat)
  library(ggplot2)
  library(optparse)
})

option_list <- list(
  make_option("--rds",                   type = "character"),
  make_option("--sample",                type = "character", default = "sample"),
  make_option("--nFeatureRNA_floor",     type = "double",    default = NA_real_),
  make_option("--nFeatureRNA_ceiling",   type = "double",    default = NA_real_),
  make_option("--nCountRNA_floor",       type = "double",    default = NA_real_),
  make_option("--nCountRNA_ceiling",     type = "double",    default = NA_real_),
  make_option("--pct_mito_floor",        type = "double",    default = NA_real_),
  make_option("--pct_mito_ceiling",      type = "double",    default = NA_real_),
  make_option("--pct_ribo_floor",        type = "double",    default = NA_real_),
  make_option("--pct_ribo_ceiling",      type = "double",    default = NA_real_),
  make_option("--ambientRNA_thres",      type = "double",    default = NA_real_),
  make_option("--log10GenesPerUMI_thres",type = "double",    default = NA_real_)
)
opt <- parse_args(OptionParser(option_list = option_list))

s.obj <- readRDS(opt\$rds)
cells_before <- ncol(s.obj)

# ── Add ribosomal % if not already present ─────────────────────────────────
if (!"percent.ribo" %in% colnames(s.obj@meta.data)) {
  s.obj[["percent.ribo"]] <- PercentageFeatureSet(s.obj, pattern = "^RP[SL]")
}

# ── Add log10GenesPerUMI if not already present ────────────────────────────
if (!"log10GenesPerUMI" %in% colnames(s.obj@meta.data)) {
  s.obj[["log10GenesPerUMI"]] <- log10(s.obj\$nFeature_RNA) / log10(s.obj\$nCount_RNA)
}

# ── Filtering function ─────────────────────────────────────────────────────
s3.filter <- function(s.obj, opt) {
  if (!is.na(opt\$nFeatureRNA_floor))
    s.obj <- subset(s.obj, subset = nFeature_RNA > opt\$nFeatureRNA_floor)
  if (!is.na(opt\$nFeatureRNA_ceiling))
    s.obj <- subset(s.obj, subset = nFeature_RNA < opt\$nFeatureRNA_ceiling)
  if (!is.na(opt\$nCountRNA_floor))
    s.obj <- subset(s.obj, subset = nCount_RNA > opt\$nCountRNA_floor)
  if (!is.na(opt\$nCountRNA_ceiling))
    s.obj <- subset(s.obj, subset = nCount_RNA < opt\$nCountRNA_ceiling)
  if (!is.na(opt\$pct_mito_floor))
    s.obj <- subset(s.obj, subset = percent.mt > opt\$pct_mito_floor)
  if (!is.na(opt\$pct_mito_ceiling))
    s.obj <- subset(s.obj, subset = percent.mt < opt\$pct_mito_ceiling)
  if (!is.na(opt\$pct_ribo_floor))
    s.obj <- subset(s.obj, subset = percent.ribo > opt\$pct_ribo_floor)
  if (!is.na(opt\$pct_ribo_ceiling))
    s.obj <- subset(s.obj, subset = percent.ribo < opt\$pct_ribo_ceiling)
  if (!is.na(opt\$ambientRNA_thres) && "AmbientRNA" %in% colnames(s.obj@meta.data))
    s.obj <- subset(s.obj, subset = AmbientRNA < opt\$ambientRNA_thres)
  if (!is.na(opt\$log10GenesPerUMI_thres))
    s.obj <- subset(s.obj, subset = log10GenesPerUMI >= opt\$log10GenesPerUMI_thres)
  return(s.obj)
}

s.obj <- s3.filter(s.obj, opt)
cells_after <- ncol(s.obj)
message(sprintf("Filtering: %d → %d cells (removed %d)", cells_before, cells_after, cells_before - cells_after))

# ── Post-filter QC violin ──────────────────────────────────────────────────
features_to_plot <- intersect(
  c("nFeature_RNA", "nCount_RNA", "percent.mt", "percent.ribo", "log10GenesPerUMI"),
  colnames(s.obj@meta.data)
)
p <- VlnPlot(s.obj, features = features_to_plot, ncol = 3, pt.size = 0)
ggsave("qc_violin_s3_postfilter.png", p,
       width = 4 * min(3, length(features_to_plot)), height = 5, dpi = 150)

# ── Filter summary ─────────────────────────────────────────────────────────
write.csv(data.frame(
  sample             = opt\$sample,
  cells_before       = cells_before,
  cells_after        = cells_after,
  cells_removed      = cells_before - cells_after,
  pct_removed        = round((cells_before - cells_after) / cells_before * 100, 2),
  nFeatureRNA_floor  = opt\$nFeatureRNA_floor,
  nFeatureRNA_ceiling= opt\$nFeatureRNA_ceiling,
  nCountRNA_floor    = opt\$nCountRNA_floor,
  nCountRNA_ceiling  = opt\$nCountRNA_ceiling,
  pct_mito_ceiling   = opt\$pct_mito_ceiling,
  pct_ribo_floor     = opt\$pct_ribo_floor,
  ambientRNA_thres   = opt\$ambientRNA_thres,
  log10GenesPerUMI_thres = opt\$log10GenesPerUMI_thres
), "qc_filter_stats.csv", row.names = FALSE)

saveRDS(s.obj, paste0(opt\$sample, "_s3.rds"))
message("Step 3 done.")
REOF

    Rscript run_filter.R \\
        --rds    ${seurat_rds} \\
        --sample "${sample}" \\
        ${args}
    """
}
