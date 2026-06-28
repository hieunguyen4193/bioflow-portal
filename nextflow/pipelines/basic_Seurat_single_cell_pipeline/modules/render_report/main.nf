process RENDER_REPORT {
    tag "${sample}"
    publishDir "${params.outdir}/s8a_report", mode: "copy"

    input:
    tuple val(sample), path(seurat_rds)
    path(rmd_file)
    path(helper_functions)
    path(import_libraries)

    output:
    path("${sample}_preliminary_analysis.html"), emit: report_html

    script:
    """
    mkdir -p src
    cp ${helper_functions} src/helper_functions.R
    cp ${import_libraries} src/import_libraries.R
    mkdir -p rmd
    cp ${rmd_file} rmd/preliminary_analysis.Rmd

    cat > render_report.R << 'REOF'
suppressPackageStartupMessages({
  library(rmarkdown)
})

rmarkdown::render(
  input       = "rmd/preliminary_analysis.Rmd",
  output_file = "${sample}_preliminary_analysis.html",
  output_dir  = getwd(),
  params      = list(
    inputSeurat = normalizePath("${seurat_rds}"),
    outputdir   = getwd()
  ),
  envir = new.env(parent = globalenv())
)
REOF
    Rscript render_report.R
    """
}
