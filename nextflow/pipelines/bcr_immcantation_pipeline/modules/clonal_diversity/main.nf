// Step 7 — Alakazam clonal abundance and Hill diversity (rarefaction curve,
// D0-D4 continuum: species richness, Shannon, Simpson).
process CLONAL_DIVERSITY {
    tag "${subject}"
    publishDir "${params.outdir}/s7_clonal_diversity/${subject}", mode: 'copy'

    input:
    tuple val(subject), path(shm_table)
    val nboot

    output:
    tuple val(subject), path("${subject}_clone_abundance.tsv"),  emit: abundance_table
    tuple val(subject), path("${subject}_diversity_curve.tsv"),  emit: diversity_table
    path "${subject}_clone_abundance.png",                       emit: abundance_plot, optional: true
    path "${subject}_diversity_curve.png",                       emit: diversity_plot, optional: true

    script:
    """
    cat > run_diversity.R << 'REOF'
suppressPackageStartupMessages({
  library(alakazam)
  library(airr)
  library(ggplot2)
})

db <- airr::read_rearrangement("${shm_table}")

abund <- countClones(db, clone = "clone_id", copy = NULL)
write.table(abund, "${subject}_clone_abundance.tsv", sep = "\\t", row.names = FALSE, quote = FALSE)

p_abund <- ggplot(head(abund[order(-abund\$seq_count), ], 30),
                   aes(x = reorder(clone_id, -seq_count), y = seq_count)) +
  geom_col(fill = "steelblue") +
  theme_bw() +
  theme(axis.text.x = element_text(angle = 90, hjust = 1, size = 6)) +
  xlab("Clone ID") + ylab("Sequence count") +
  ggtitle("${subject}: top 30 clones by abundance")
ggsave("${subject}_clone_abundance.png", p_abund, width = 9, height = 5, dpi = 150)

n_clones <- length(unique(db\$clone_id))
if (n_clones >= 2) {
  curve <- alphaDiversity(
    db,
    clone   = "clone_id",
    min_q   = 0, max_q = 4, step_q = 0.1,
    nboot   = ${nboot}
  )
  write.table(curve@diversity, "${subject}_diversity_curve.tsv", sep = "\\t", row.names = FALSE, quote = FALSE)

  p_div <- plotDiversityCurve(curve, silent = TRUE) +
    ggtitle("${subject}: Hill diversity (D0-D4)")
  ggsave("${subject}_diversity_curve.png", p_div, width = 7, height = 5, dpi = 150)
} else {
  message("Fewer than 2 clones for ${subject}; skipping diversity curve.")
  write.table(data.frame(), "${subject}_diversity_curve.tsv", sep = "\\t", row.names = FALSE, quote = FALSE)
}
REOF

    Rscript run_diversity.R
    """
}
