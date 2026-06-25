// Step 04 — generate TFBS coverage profile features
process COVERAGE_PROFILE {
    tag "${sampleID}"
    publishDir { "${params.outdir}/step04_coverage_profile/${sampleID}" }, mode: 'copy'

    input:
    tuple val(sampleID), path(frag), path(frag_tbi), path(cna_100kb), path(genomecov)

    output:
    tuple val(sampleID), path("${sampleID}.preprocessed_coverage_profile"), emit: coverage_profile

    script:
    def cov_script = "${params.projectdir}/processes/generate_TFBS_features/04_generate_coverage_profile_features.sh"
    def prep_id    = "${sampleID}.preprocessed"
    """
    export PATH=/home/dockerUser/samtools/bin:/home/dockerUser/miniconda3/bin:/home/dockerUser/miniconda3/condabin:/home/dockerUser/bedtools2/bin:\$PATH
    export RESOURCE_DIR="${params.resource_dir}"
    mkdir -p workdir
    bash ${cov_script} \\
        -i ${frag} \\
        -s ${prep_id} \\
        -o workdir \\
        -p ${params.projectdir} \\
        -a ${cna_100kb} \\
        -v ${genomecov}

    cp -r workdir/04_coverage_profile_features/${prep_id}_coverage_profile ./
    """
}
