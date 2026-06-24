process REGRESS_OUT {
    tag "${sample}"
    publishDir "${params.outdir}/s7_regress_out",               mode: "copy"
    publishDir "${params.outdir}/intermediates/s7_regress_out", mode: "copy", pattern: "*_s7.rds"

    input:
    tuple val(sample), path(seurat_rds)
    val  features_to_regressOut
    val  regressOut_mode

    output:
    tuple val(sample), path("${sample}_s7.rds"), emit: seurat_rds

    script:
    """
    cat > run_s7.R << 'REOF'
suppressPackageStartupMessages({
  library(Seurat)
  library(optparse)
})

option_list <- list(
  make_option("--rds",                    type = "character"),
  make_option("--sample",                 type = "character", default = "sample"),
  make_option("--features_to_regressOut", type = "character", default = "none"),
  make_option("--regressOut_mode",        type = "character", default = "alternative")
)
opt <- parse_args(OptionParser(option_list = option_list))

s.obj <- readRDS(opt\$rds)

s7.cellFactorRegressOut <- function(s.obj, features_to_regressOut, regressOut_mode = "alternative") {
  if (!is.null(features_to_regressOut) && features_to_regressOut != "none") {
    s.obj\$CC.Difference <- s.obj\$S.Score - s.obj\$G2M.Score

    if (regressOut_mode == "normal") {
      vars <- trimws(strsplit(features_to_regressOut, ",")[[1]])
      message("Regressing out (normal): ", paste(vars, collapse = ", "))
      s.obj <- ScaleData(s.obj, vars.to.regress = vars, features = rownames(s.obj))
    } else if (regressOut_mode == "alternative") {
      message("Regressing out CC.Difference (alternative)")
      s.obj <- ScaleData(s.obj, vars.to.regress = "CC.Difference", features = rownames(s.obj))
    } else {
      stop("regressOut_mode must be 'normal' or 'alternative'. Got: ", regressOut_mode)
    }
  } else {
    message("features_to_regressOut is none — skipping regress-out.")
  }
  return(s.obj)
}

s.obj <- s7.cellFactorRegressOut(
  s.obj,
  features_to_regressOut = opt\$features_to_regressOut,
  regressOut_mode        = opt\$regressOut_mode
)

saveRDS(s.obj, paste0(opt\$sample, "_s7.rds"))
message("Step 7 complete.")
REOF

    Rscript run_s7.R \\
        --rds                    "${seurat_rds}" \\
        --sample                 "${sample}" \\
        --features_to_regressOut "${features_to_regressOut}" \\
        --regressOut_mode        "${regressOut_mode}"
    """
}
