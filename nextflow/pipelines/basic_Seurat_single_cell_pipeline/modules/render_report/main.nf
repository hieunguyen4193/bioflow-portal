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

    Rscript - << 'REOF'
suppressPackageStartupMessages(library(rmarkdown))
wd <- getwd()
input_assay <- if (tolower("${params.use_sctransform}") == "true") "SCT" else "RNA"
rmarkdown::render(
  input         = file.path(wd, "preliminary_analysis.Rmd"),
  output_file   = "${sample}_preliminary_analysis.html",
  output_dir    = wd,
  knit_root_dir = wd,
  params        = list(
    inputSeurat = file.path(wd, "${seurat_rds}"),
    outputdir   = wd,
    input.assay = input_assay
  ),
  envir = new.env(parent = globalenv())
)
REOF
    """
}
