// Step 4 — Change-O clonal clustering: group heavy chains into clones using
// same V gene, same J gene, same junction length, and a hierarchical-clustering
// distance below the per-subject threshold from SHAZAM_THRESHOLD.
process DEFINE_CLONES {
    tag "${subject}"
    publishDir "${params.outdir}/s4_define_clones/${subject}", mode: 'copy'

    input:
    tuple val(subject), path(combined_igh_tsv), path(threshold_txt)
    val model
    val norm

    output:
    tuple val(subject), path("${subject}_clone-pass.tsv"), emit: clone_pass

    script:
    """
    THRESHOLD=\$(cat ${threshold_txt})

    DefineClones.py \\
        -d ${combined_igh_tsv} \\
        --act set \\
        --model ${model} \\
        --norm ${norm} \\
        --dist \${THRESHOLD} \\
        --outname ${subject}
    """
}
