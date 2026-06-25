// Step 04 — generate TFBS coverage profile features
process COVERAGE_PROFILE {
    tag "${sampleID}"
    publishDir { "${params.outdir}/step04_coverage_profile/${sampleID}" }, mode: 'copy'

    input:
    tuple val(sampleID), path(frag), path(cna_100kb), path(genomecov)

    output:
    tuple val(sampleID), path("${sampleID}.preprocessed_coverage_profile"), emit: coverage_profile

    script:
    def cov_script = "${params.projectdir}/processes/generate_TFBS_features/04_generate_coverage_profile_features.sh"
    def prep_id    = "${sampleID}.preprocessed"
    """
    sed 's|/mnt/NFS_190T/DATA_HIEUNGUYEN/resources/preprocessed_resources/TFBS|${params.resource_dir}/TFBS|g; s|/mnt/NFS_190T/DATA_HIEUNGUYEN/resources|${params.resource_dir}|g' ${cov_script} > patched_04.sh
    mkdir -p workdir
    bash patched_04.sh \\
        -i ${frag} \\
        -s ${prep_id} \\
        -o workdir \\
        -p ${params.projectdir} \\
        -a ${cna_100kb} \\
        -v ${genomecov}

    cp -r workdir/04_coverage_profile_features/${prep_id}_coverage_profile ./
    """
}
