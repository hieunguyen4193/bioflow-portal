// Step 9 (optional) — dowser clonal lineage trees, built with maximum
// parsimony (phangorn::pratchet) so no external phylogenetics binary
// (IgPhyML/PHYLIP) is required inside the container.
process LINEAGE_TREES {
    tag "${subject}"
    publishDir "${params.outdir}/s9_lineage_trees/${subject}", mode: 'copy'

    input:
    tuple val(subject), path(germ_pass)
    val min_seqs

    output:
    path "${subject}_trees.rds",  emit: trees_rds, optional: true
    path "${subject}_trees.pdf",  emit: trees_pdf, optional: true

    script:
    """
    cat > run_lineage.R << 'REOF'
suppressPackageStartupMessages({
  library(dowser)
  library(airr)
  library(dplyr)
})

db <- airr::read_rearrangement("${germ_pass}")

clone_sizes <- db %>% count(clone_id) %>% filter(n >= ${min_seqs})

if (nrow(clone_sizes) == 0) {
  message("No clone in ${subject} has >= ${min_seqs} sequences; skipping lineage trees.")
} else {
  db <- db %>% filter(clone_id %in% clone_sizes\$clone_id)

  clones <- formatClones(
    db,
    seq        = "sequence_alignment",
    germ       = "germline_alignment_d_mask",
    v_call     = "v_call",
    j_call     = "j_call",
    junc_len   = "junction_length",
    clone      = "clone_id",
    minseq     = ${min_seqs}
  )

  if (nrow(clones) == 0) {
    message("formatClones produced no usable clones for ${subject}; skipping.")
  } else {
    trees <- getTrees(clones, build = "pratchet")
    saveRDS(trees, "${subject}_trees.rds")

    pdf("${subject}_trees.pdf", width = 7, height = 7)
    plots <- plotTrees(trees)
    for (p in plots) print(p)
    dev.off()
  }
}
REOF

    Rscript run_lineage.R
    """
}
