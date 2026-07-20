// Step 5 — Reconstruct the germline (D-segment masked) sequence for each clone.
process CREATE_GERMLINES {
    tag "${subject}"
    publishDir "${params.outdir}/s5_create_germlines/${subject}", mode: 'copy'

    input:
    tuple val(subject), path(clone_pass)
    val species

    output:
    tuple val(subject), path("${subject}_germ-pass.tsv"), emit: germ_pass

    script:
    def germline_dir = "/usr/local/share/germlines/imgt/${species}/vdj"
    """
    CreateGermlines.py \\
        -d ${clone_pass} \\
        -r ${germline_dir} \\
        -g dmask \\
        --cloned \\
        --outname ${subject}
    """
}
