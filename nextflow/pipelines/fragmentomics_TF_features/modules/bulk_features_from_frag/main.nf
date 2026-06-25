// Generate bulk features from a pre-computed FLEN_EM_ND.tsv file
// (skips the EM/ND computation step — use when that file already exists).
process BULK_FEATURES_FROM_FRAG {
    tag "${sampleID}"
    publishDir { "${params.outdir}/bulk_features_from_frag/${sampleID}" }, mode: 'copy'

    input:
    tuple val(sampleID), path(flen_em_nd_tsv)

    output:
    tuple val(sampleID), path("${sampleID}_bulk_features"), emit: bulk_features

    script:
    def bulk_script = "${params.projectdir}/processes/generate_bulk_features_from_fragFile.sh"
    """
    mkdir -p workdir
    bash ${bulk_script} \\
        -i ${flen_em_nd_tsv} \\
        -s ${sampleID} \\
        -o workdir \\
        -p ${params.projectdir}

    cp -r workdir/${sampleID}_bulk_features ./
    """
}
