// Step 10 — Render one HTML report per subject aggregating SHM, clonal
// abundance, diversity, and gene-usage results.
process RENDER_REPORT {
    tag "${subject}"
    publishDir "${params.outdir}/s10_report", mode: "copy"

    input:
    tuple val(subject), path(shm_table), path(abundance_table), path(diversity_table), path(v_gene_usage), path(j_gene_usage), path(threshold_txt)
    path rmd_file

    output:
    path("${subject}_bcr_report.html"), emit: report_html

    script:
    """
    Rscript - << 'REOF'
suppressPackageStartupMessages(library(rmarkdown))
wd <- getwd()
rmarkdown::render(
  input         = "${rmd_file}",
  output_file   = "${subject}_bcr_report.html",
  output_dir    = wd,
  knit_root_dir = wd,
  params        = list(
    subject         = "${subject}",
    shm_table       = file.path(wd, "${shm_table}"),
    abundance_table = file.path(wd, "${abundance_table}"),
    diversity_table = file.path(wd, "${diversity_table}"),
    v_gene_usage    = file.path(wd, "${v_gene_usage}"),
    j_gene_usage    = file.path(wd, "${j_gene_usage}"),
    threshold_txt   = file.path(wd, "${threshold_txt}")
  ),
  envir = new.env(parent = globalenv())
)
REOF
    """
}
