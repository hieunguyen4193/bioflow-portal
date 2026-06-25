// Generate genome-wide binwise features from short, long, and full BAM files.
// short/long/full BAMs are typically outputs of step01 (PROCESS_BAM).
process BINWISE_FEATURES {
    tag "${sampleID}"
    publishDir { "${params.outdir}/binwise_features/${sampleID}" }, mode: 'copy'

    input:
    tuple val(sampleID), path(short_bam), path(short_bai), path(long_bam), path(long_bai), path(full_bam), path(full_bai)

    output:
    tuple val(sampleID), path("${sampleID}_binwise_features"), emit: binwise_features

    script:
    def binwise_rscript = "${params.projectdir}/src/generate_binwise_features.R"
    """
    mkdir -p ${sampleID}_binwise_features
    Rscript ${binwise_rscript} \\
        -s ${short_bam} \\
        -l ${long_bam} \\
        -f ${full_bam} \\
        -o ${sampleID}_binwise_features \\
        -i ${sampleID}
    """
}
