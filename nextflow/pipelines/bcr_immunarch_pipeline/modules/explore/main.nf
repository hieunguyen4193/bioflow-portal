// Step 2 — Basic repertoire exploration (clone volume / length / count).
process EXPLORE {
    publishDir "${params.outdir}/s2_explore", mode: 'copy'

    input:
    path immdata_rds
    val explore_method

    output:
    path "explore.tsv", emit: table
    path "explore.png", emit: plot

    script:
    """
    cat > run_explore.R << 'REOF'
suppressPackageStartupMessages(library(immunarch))
suppressPackageStartupMessages(library(ggplot2))

immdata <- readRDS("${immdata_rds}")

result <- repExplore(immdata\$data, .method = "${explore_method}")
write.table(result, "explore.tsv", sep = "\\t", row.names = FALSE, quote = FALSE)

p <- tryCatch(vis(result), error = function(e) NULL)
if (is.null(p)) {
  p <- ggplot() + annotate("text", x = 0, y = 0, label = "explore plot unavailable") + theme_void()
}
ggsave("explore.png", p, width = 7, height = 5, dpi = 150)
REOF

    Rscript run_explore.R
    """
}
