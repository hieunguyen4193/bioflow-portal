// Step 05 — generate WPS / IFS / FDI features
process WPS_IFS_FDI {
    tag "${sampleID}"
    publishDir "${params.outdir}/step05_wps_ifs_fdi/${sampleID}", mode: 'copy'

    input:
    tuple val(sampleID), path(frag), path(chrom_features)

    output:
    tuple val(sampleID), path("${sampleID}.preprocessed_WPS_IFS_FDI_features"), emit: wps_features

    script:
    def wps_script = "${params.projectdir}/processes/generate_TFBS_features/05_generate_WPS_IFS_FDI_features.sh"
    def prep_id    = "${sampleID}.preprocessed"
    """
    mkdir -p workdir
    bash ${wps_script} \\
        -i ${frag} \\
        -s ${prep_id} \\
        -o workdir \\
        -p ${params.projectdir} \\
        -c ${chrom_features}

    cp -r workdir/05_WPS_IFS_FDI/${prep_id}_WPS_IFS_FDI_features ./
    """
}
