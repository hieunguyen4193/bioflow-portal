// Step 6 — SHazaM somatic hypermutation (SHM) analysis: observed mutation
// frequency per sequence (replacement + silent, CDR + FWR), plus a summary
// plot of mutation frequency by isotype (c_call) when available.
process SHM_ANALYSIS {
    tag "${subject}"
    publishDir "${params.outdir}/s6_shm_analysis/${subject}", mode: 'copy'

    input:
    tuple val(subject), path(germ_pass)

    output:
    tuple val(subject), path("${subject}_shm.tsv"), emit: shm_table
    path "${subject}_shm_by_isotype.png",           emit: plot, optional: true

    script:
    """
    cat > run_shm.R << 'REOF'
suppressPackageStartupMessages({
  library(shazam)
  library(airr)
  library(ggplot2)
  library(dplyr)
})

db <- airr::read_rearrangement("${germ_pass}")

db <- observedMutations(
  db,
  sequenceColumn         = "sequence_alignment",
  germlineColumn         = "germline_alignment_d_mask",
  regionDefinition       = IMGT_V,
  frequency              = TRUE,
  combine                = TRUE,
  nproc                  = 1
)

airr::write_rearrangement(db, "${subject}_shm.tsv")

if ("c_call" %in% colnames(db) && "mu_freq" %in% colnames(db)) {
  plot_df <- db %>% filter(!is.na(c_call), !is.na(mu_freq))
  if (nrow(plot_df) > 0) {
    p <- ggplot(plot_df, aes(x = c_call, y = mu_freq, fill = c_call)) +
      geom_boxplot(outlier.size = 0.5) +
      theme_bw() +
      theme(axis.text.x = element_text(angle = 45, hjust = 1), legend.position = "none") +
      ylab("Mutation frequency") + xlab("Isotype (c_call)") +
      ggtitle("${subject}: somatic hypermutation frequency by isotype")
    ggsave("${subject}_shm_by_isotype.png", p, width = 7, height = 5, dpi = 150)
  }
}
REOF

    Rscript run_shm.R
    """
}
