// Step 3 — Clonal space homeostasis / proportion of top, rare, or
// hyperexpanded clonotypes.
process CLONALITY {
    publishDir "${params.outdir}/s3_clonality", mode: 'copy'

    input:
    path immdata_rds
    val clonality_method

    output:
    path "clonality.tsv", emit: table
    path "clonality.png", emit: plot

    script:
    """
    cat > run_clonality.R << 'REOF'
suppressPackageStartupMessages(library(immunarch))
suppressPackageStartupMessages(library(ggplot2))

immdata <- readRDS("${immdata_rds}")

result <- repClonality(immdata\$data, .method = "${clonality_method}")
write.table(as.data.frame(result), "clonality.tsv", sep = "\\t", row.names = TRUE, quote = FALSE)

p <- tryCatch(vis(result), error = function(e) NULL)
if (is.null(p)) {
  p <- ggplot() + annotate("text", x = 0, y = 0, label = "clonality plot unavailable") + theme_void()
}
ggsave("clonality.png", p, width = 7, height = 5, dpi = 150)
REOF

    Rscript run_clonality.R
    """
}
