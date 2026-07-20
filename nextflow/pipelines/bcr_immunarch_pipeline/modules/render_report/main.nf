// Step 9 — Render one HTML report aggregating sample summary, exploration,
// clonality, diversity, gene usage, and overlap. (Clonal tracking and k-mer
// analysis are optional side-outputs, not embedded in this report.)
process RENDER_REPORT {
    publishDir "${params.outdir}/s9_report", mode: 'copy'

    input:
    path sample_summary
    path explore_table
    path explore_png
    path clonality_table
    path clonality_png
    path diversity_table
    path diversity_png
    path gene_usage_table
    path gene_usage_png
    path overlap_table
    path overlap_png
    path rmd_file

    output:
    path "bcr_immunarch_report.html", emit: report_html

    script:
    """
    Rscript - << 'REOF'
suppressPackageStartupMessages(library(rmarkdown))
wd <- getwd()
rmarkdown::render(
  input         = "${rmd_file}",
  output_file   = "bcr_immunarch_report.html",
  output_dir    = wd,
  knit_root_dir = wd,
  params        = list(
    sample_summary   = "${sample_summary}",
    explore_table    = "${explore_table}",
    explore_png      = "${explore_png}",
    clonality_table  = "${clonality_table}",
    clonality_png    = "${clonality_png}",
    diversity_table  = "${diversity_table}",
    diversity_png    = "${diversity_png}",
    gene_usage_table = "${gene_usage_table}",
    gene_usage_png   = "${gene_usage_png}",
    overlap_table    = "${overlap_table}",
    overlap_png      = "${overlap_png}"
  ),
  envir = new.env(parent = globalenv())
)
REOF
    """
}
