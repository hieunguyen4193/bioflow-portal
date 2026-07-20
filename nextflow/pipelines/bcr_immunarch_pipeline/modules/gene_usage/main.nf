// Step 5 — V/J gene usage. Uses immunarch's built-in IG gene reference sets
// (e.g. "hs.ighv"); falls back to a manual per-sample gene-count table built
// straight from the loaded clonotype tables if the reference name isn't
// recognized by the installed immunarch version.
process GENE_USAGE {
    publishDir "${params.outdir}/s5_gene_usage", mode: 'copy'

    input:
    path immdata_rds
    val gene_reference
    val gene_col

    output:
    path "gene_usage.tsv", emit: table
    path "gene_usage.png", emit: plot

    script:
    """
    cat > run_gene_usage.R << 'REOF'
suppressPackageStartupMessages(library(immunarch))
suppressPackageStartupMessages(library(ggplot2))

immdata <- readRDS("${immdata_rds}")

result <- tryCatch(
  geneUsage(immdata\$data, .gene = "${gene_reference}"),
  error = function(e) {
    message("geneUsage() with reference '${gene_reference}' failed (", conditionMessage(e), "); falling back to manual counts.")
    NULL
  }
)

if (!is.null(result)) {
  write.table(result, "gene_usage.tsv", sep = "\\t", row.names = FALSE, quote = FALSE)
  p <- tryCatch(vis(result), error = function(e) NULL)
} else {
  samples    <- rep(names(immdata\$data), sapply(immdata\$data, nrow))
  gene_values <- unlist(lapply(immdata\$data, function(df) df[["${gene_col}"]]))
  counts <- as.data.frame(table(Sample = samples, Gene = gene_values))
  colnames(counts) <- c("Sample", "Gene", "n")
  write.table(counts, "gene_usage.tsv", sep = "\\t", row.names = FALSE, quote = FALSE)

  p <- ggplot(counts, aes(x = reorder(Gene, -n), y = n, fill = Sample)) +
    geom_col(position = "dodge") +
    theme_bw() +
    theme(axis.text.x = element_text(angle = 90, hjust = 1, size = 6)) +
    xlab("${gene_col}") + ylab("Count")
}

if (is.null(p)) {
  p <- ggplot() + annotate("text", x = 0, y = 0, label = "gene usage plot unavailable") + theme_void()
}
ggsave("gene_usage.png", p, width = 9, height = 5, dpi = 150)
REOF

    Rscript run_gene_usage.R
    """
}
