// Step 4 — Repertoire diversity estimation.
process DIVERSITY {
    publishDir "${params.outdir}/s4_diversity", mode: 'copy'

    input:
    path immdata_rds
    val diversity_method

    output:
    path "diversity.tsv", emit: table
    path "diversity.png", emit: plot

    script:
    """
    cat > run_diversity.R << 'REOF'
suppressPackageStartupMessages(library(immunarch))
suppressPackageStartupMessages(library(ggplot2))

immdata <- readRDS("${immdata_rds}")

result <- repDiversity(immdata\$data, .method = "${diversity_method}")
write.table(as.data.frame(result), "diversity.tsv", sep = "\\t", row.names = FALSE, quote = FALSE)

p <- tryCatch(vis(result), error = function(e) NULL)
if (is.null(p)) {
  p <- ggplot() + annotate("text", x = 0, y = 0, label = "diversity plot unavailable") + theme_void()
}
ggsave("diversity.png", p, width = 7, height = 5, dpi = 150)
REOF

    Rscript run_diversity.R
    """
}
