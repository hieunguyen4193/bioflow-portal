process RENDER_REPORT {
    tag "${sample}"
    container 'tronghieunguyen/single_cell_pipeline'
    publishDir "${params.outdir}/s8a_report", mode: "copy"

    input:
    tuple val(sample), path(seurat_rds)

    output:
    path("${sample}_preliminary_analysis.html"), emit: report_html

    script:
    """
    cat > render_report.R << 'REOF'
suppressPackageStartupMessages({
  library(rmarkdown)
})

rmd_src  <- file.path("${projectDir}", "rmd", "preliminary_analysis.Rmd")
out_file <- paste0("${sample}_preliminary_analysis.html")
outdir   <- getwd()

rmarkdown::render(
  input       = rmd_src,
  output_file = out_file,
  output_dir  = outdir,
  params      = list(
    inputSeurat = normalizePath("${seurat_rds}"),
    outputdir   = outdir
  ),
  envir = new.env(parent = globalenv())
)
REOF
    Rscript render_report.R
    """
}
