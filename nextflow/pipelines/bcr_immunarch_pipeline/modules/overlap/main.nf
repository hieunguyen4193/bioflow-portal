// Step 7 — Public/repertoire overlap between samples. Self-skips (writes a
// placeholder) when fewer than 2 samples are present.
process OVERLAP {
    publishDir "${params.outdir}/s7_overlap", mode: 'copy'

    input:
    path immdata_rds
    val overlap_method

    output:
    path "overlap.tsv", emit: table
    path "overlap.png", emit: plot

    script:
    """
    cat > run_overlap.R << 'REOF'
suppressPackageStartupMessages(library(immunarch))
suppressPackageStartupMessages(library(ggplot2))

immdata <- readRDS("${immdata_rds}")

if (length(immdata\$data) < 2) {
  writeLines("# only 1 sample present; overlap needs >= 2", "overlap.tsv")
  p <- ggplot() + annotate("text", x = 0, y = 0, label = "overlap needs >= 2 samples") + theme_void()
} else {
  result <- tryCatch(
    repOverlap(immdata\$data, .method = "${overlap_method}"),
    error = function(e) {
      message("repOverlap() failed: ", conditionMessage(e))
      NULL
    }
  )
  if (!is.null(result)) {
    write.table(as.data.frame(result), "overlap.tsv", sep = "\\t", row.names = TRUE, quote = FALSE)
    p <- tryCatch(vis(result), error = function(e) NULL)
  } else {
    writeLines("# overlap unavailable", "overlap.tsv")
    p <- NULL
  }
  if (is.null(p)) {
    p <- ggplot() + annotate("text", x = 0, y = 0, label = "overlap plot unavailable") + theme_void()
  }
}
ggsave("overlap.png", p, width = 7, height = 6, dpi = 150)
REOF

    Rscript run_overlap.R
    """
}
