// Step 6 (optional) — Track the top N clonotypes' abundance across samples.
// Only meaningful with >= 2 samples; self-skips otherwise.
process CLONAL_TRACKING {
    publishDir "${params.outdir}/s6_clonal_tracking", mode: 'copy'

    input:
    path immdata_rds
    val top_n_clonotypes

    output:
    path "clonal_tracking.tsv", emit: table
    path "clonal_tracking.png", emit: plot

    script:
    """
    cat > run_tracking.R << 'REOF'
suppressPackageStartupMessages(library(immunarch))
suppressPackageStartupMessages(library(ggplot2))

immdata <- readRDS("${immdata_rds}")

if (length(immdata\$data) < 2) {
  writeLines("# only 1 sample present; clonal tracking needs >= 2", "clonal_tracking.tsv")
  p <- ggplot() + annotate("text", x = 0, y = 0, label = "clonal tracking needs >= 2 samples") + theme_void()
} else {
  result <- tryCatch(
    trackClonotypes(immdata\$data, .which = ${top_n_clonotypes}, .col = "aa"),
    error = function(e) {
      message("trackClonotypes() failed: ", conditionMessage(e))
      NULL
    }
  )
  if (!is.null(result)) {
    write.table(result, "clonal_tracking.tsv", sep = "\\t", row.names = FALSE, quote = FALSE)
    p <- tryCatch(vis(result), error = function(e) NULL)
  } else {
    writeLines("# clonal tracking unavailable", "clonal_tracking.tsv")
    p <- NULL
  }
  if (is.null(p)) {
    p <- ggplot() + annotate("text", x = 0, y = 0, label = "clonal tracking plot unavailable") + theme_void()
  }
}
ggsave("clonal_tracking.png", p, width = 8, height = 5, dpi = 150)
REOF

    Rscript run_tracking.R
    """
}
