// Step 03 — generate CNA features (bin100kb + bin1M) needed by coverage profile step
process CNA_FEATURES {
    tag "${sampleID}"
    publishDir { "${params.outdir}/step03_cna_features/${sampleID}" }, mode: 'copy'

    input:
    tuple val(sampleID), path(preprocessed_bam)
    tuple val(sampleID2), path(preprocessed_bai)

    output:
    tuple val(sampleID), path("${sampleID}.preprocessed.bin100kb.bed"), emit: cna_100kb
    tuple val(sampleID), path("${sampleID}.preprocessed.bin1M.bed"),    emit: cna_1m

    script:
    def cna_script = "${params.projectdir}/processes/generate_TFBS_features/03_generate_CNA_features_for_TFBS_coverage.sh"
    def prep_id    = "${sampleID}.preprocessed"
    """
    export PATH=/home/dockerUser/samtools/bin:/home/dockerUser/miniconda3/bin:/home/dockerUser/miniconda3/condabin:/home/dockerUser/bedtools2/bin:\$PATH
    mkdir -p workdir
    bash ${cna_script} \\
        -i ${preprocessed_bam} \\
        -s ${prep_id} \\
        -o workdir \\
        -p ${params.projectdir}

    cp workdir/03_CNA_for_coverage_profile/${prep_id}/${prep_id}.bin100kb.bed ./
    cp workdir/03_CNA_for_coverage_profile/${prep_id}/${prep_id}.bin1M.bed    ./
    """
}
