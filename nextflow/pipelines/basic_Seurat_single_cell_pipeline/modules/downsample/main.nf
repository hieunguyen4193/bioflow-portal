process DOWNSAMPLE {
    tag "${sample}"
    publishDir "${params.outdir}/s1b_downsample", mode: "copy"

    input:
    tuple val(sample), path(seurat_rds)
    val  downsample_type    // "percent" | "number"
    val  downsample_value   // numeric: percent (0-100) or cell count

    output:
    tuple val(sample), path("${sample}_s1b.rds"), emit: seurat_rds

    script:
    """
    cat > run_downsample.R << 'REOF'
suppressPackageStartupMessages(library(Seurat))
suppressPackageStartupMessages(library(optparse))

option_list <- list(
  make_option("--rds",    type = "character"),
  make_option("--sample", type = "character", default = "sample"),
  make_option("--type",   type = "character", default = "percent"),
  make_option("--value",  type = "character", default = "100")
)
opt <- parse_args(OptionParser(option_list = option_list))

s.obj <- readRDS(opt\$rds)
n_before <- ncol(s.obj)
value    <- as.numeric(opt\$value)

if (opt\$type == "percent") {
  if (value <= 0 || value >= 100) {
    message("Downsampling percent must be between 0 and 100, got ", value, " — skipping.")
  } else {
    n_keep <- floor(n_before * value / 100)
    set.seed(42)
    s.obj <- s.obj[, sample(colnames(s.obj), n_keep)]
    message(sprintf("Downsampled to %.0f%% — %d → %d cells", value, n_before, ncol(s.obj)))
  }
} else if (opt\$type == "number") {
  n_keep <- min(as.integer(value), n_before)
  set.seed(42)
  s.obj <- s.obj[, sample(colnames(s.obj), n_keep)]
  message(sprintf("Downsampled to %d cells — %d → %d cells", n_keep, n_before, ncol(s.obj)))
} else {
  message("Unknown downsample type '", opt\$type, "' — skipping.")
}

saveRDS(s.obj, paste0(opt\$sample, "_s1b.rds"))
message("Downsampling done.")
REOF

    Rscript run_downsample.R \\
        --rds    "${seurat_rds}" \\
        --sample "${sample}" \\
        --type   "${downsample_type ?: 'percent'}" \\
        --value  "${downsample_value ?: 100}"
    """
}
