// Step 06 — generate RFE (Relative Fragment End) features
process RFE_FEATURES {
    tag "${sampleID}"
    publishDir "${params.outdir}/step06_rfe_features/${sampleID}", mode: 'copy'

    input:
    tuple val(sampleID), path(frag)

    output:
    tuple val(sampleID), path("${sampleID}.preprocessed_RFE_features"), emit: rfe_features

    script:
    def rfe_script = "${params.projectdir}/processes/generate_TFBS_features/06_generate_RFE_features.sh"
    def prep_id    = "${sampleID}.preprocessed"
    """
    mkdir -p workdir
    bash ${rfe_script} \\
        -i ${frag} \\
        -s ${prep_id} \\
        -o workdir \\
        -p ${params.projectdir}

    cp -r workdir/06_RFE_features/${prep_id}_RFE_features ./
    """
}
