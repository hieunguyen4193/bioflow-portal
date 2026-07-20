// Step 8 (optional) — CDR3 k-mer frequency analysis across all samples.
process KMER_ANALYSIS {
    publishDir "${params.outdir}/s8_kmer_analysis", mode: 'copy'

    input:
    path immdata_rds
    val kmer_k
    val kmer_head

    output:
    path "kmers.tsv", emit: table
    path "kmers.png", emit: plot

    script:
    """
    cat > run_kmer.R << 'REOF'
suppressPackageStartupMessages(library(immunarch))
suppressPackageStartupMessages(library(ggplot2))

immdata <- readRDS("${immdata_rds}")

result <- tryCatch(
  getKmers(immdata\$data, .k = ${kmer_k}),
  error = function(e) {
    message("getKmers() failed: ", conditionMessage(e))
    NULL
  }
)

if (!is.null(result)) {
  write.table(result, "kmers.tsv", sep = "\\t", row.names = FALSE, quote = FALSE)
  p <- tryCatch(vis(result, .head = ${kmer_head}), error = function(e) NULL)
} else {
  writeLines("# k-mer analysis unavailable", "kmers.tsv")
  p <- NULL
}

if (is.null(p)) {
  p <- ggplot() + annotate("text", x = 0, y = 0, label = "k-mer plot unavailable") + theme_void()
}
ggsave("kmers.png", p, width = 7, height = 5, dpi = 150)
REOF

    Rscript run_kmer.R
    """
}
