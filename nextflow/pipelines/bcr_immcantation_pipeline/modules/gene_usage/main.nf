// Step 8 — Alakazam V/J gene usage (gene- and family-level).
process GENE_USAGE {
    tag "${subject}"
    publishDir "${params.outdir}/s8_gene_usage/${subject}", mode: 'copy'

    input:
    tuple val(subject), path(shm_table)

    output:
    tuple val(subject), path("${subject}_v_gene_usage.tsv"), path("${subject}_j_gene_usage.tsv"), emit: gene_usage_tables
    path "${subject}_v_gene_usage.png",                                                           emit: v_plot, optional: true
    path "${subject}_j_gene_usage.png",                                                           emit: j_plot, optional: true

    script:
    """
    cat > run_gene_usage.R << 'REOF'
suppressPackageStartupMessages({
  library(alakazam)
  library(airr)
  library(ggplot2)
})

db <- airr::read_rearrangement("${shm_table}")

v_usage <- countGenes(db, gene = "v_call", mode = "gene")
j_usage <- countGenes(db, gene = "j_call", mode = "gene")

write.table(v_usage, "${subject}_v_gene_usage.tsv", sep = "\\t", row.names = FALSE, quote = FALSE)
write.table(j_usage, "${subject}_j_gene_usage.tsv", sep = "\\t", row.names = FALSE, quote = FALSE)

p_v <- ggplot(v_usage, aes(x = reorder(gene, -seq_freq), y = seq_freq)) +
  geom_col(fill = "darkorange") +
  theme_bw() +
  theme(axis.text.x = element_text(angle = 90, hjust = 1, size = 6)) +
  xlab("V gene") + ylab("Frequency") +
  ggtitle("${subject}: V gene usage")
ggsave("${subject}_v_gene_usage.png", p_v, width = 9, height = 5, dpi = 150)

p_j <- ggplot(j_usage, aes(x = reorder(gene, -seq_freq), y = seq_freq)) +
  geom_col(fill = "seagreen") +
  theme_bw() +
  theme(axis.text.x = element_text(angle = 90, hjust = 1, size = 8)) +
  xlab("J gene") + ylab("Frequency") +
  ggtitle("${subject}: J gene usage")
ggsave("${subject}_j_gene_usage.png", p_j, width = 6, height = 5, dpi = 150)
REOF

    Rscript run_gene_usage.R
    """
}
