// Step 06 — generate RFE (Relative Fragment End) features
process RFE_FEATURES {
    tag "${sampleID}"
    publishDir { "${params.outdir}/step06_rfe_features/${sampleID}" }, mode: 'copy'

    input:
    tuple val(sampleID), path(frag), path(frag_tbi)

    output:
    tuple val(sampleID), path("${sampleID}.preprocessed_RFE_features"), emit: rfe_features

    script:
    def rfe_script = "${params.projectdir}/processes/generate_TFBS_features/06_generate_RFE_features.sh"
    def prep_id    = "${sampleID}.preprocessed"
    """
    sed 's|/mnt/NFS_190T/DATA_HIEUNGUYEN/resources/preprocessed_resources/TFBS|${params.resource_dir}/TFBS|g; s|/mnt/NFS_190T/DATA_HIEUNGUYEN/resources|${params.resource_dir}|g' ${rfe_script} > patched_06.sh
    export PATH=/home/dockerUser/samtools/bin:/home/dockerUser/miniconda3/bin:/home/dockerUser/miniconda3/condabin:/home/dockerUser/bedtools2/bin:\$PATH
    mkdir -p workdir
    bash patched_06.sh \\
        -i ${frag} \\
        -s ${prep_id} \\
        -o workdir \\
        -p ${params.projectdir}

    cp -r workdir/06_RFE_features/${prep_id}_RFE_features ./
    """
}
