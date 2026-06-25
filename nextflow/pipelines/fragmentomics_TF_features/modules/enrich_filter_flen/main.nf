// Filter BAM by fragment length: keeps fragments <150 bp OR >175 bp
// (nucleosome-free + nucleosome-bound populations), produces three BAM outputs.
process ENRICH_FILTER_FLEN {
    tag "${sampleID}"
    publishDir { "${params.outdir}/enrich_filter_flen/${sampleID}" }, mode: 'copy'

    input:
    tuple val(sampleID), path(bam), path(bai)

    output:
    tuple val(sampleID), path("${sampleID}/${sampleID}_50_150.filtered.bam"),          emit: short_bam
    tuple val(sampleID), path("${sampleID}/${sampleID}_175_350.filtered.bam"),         emit: long_bam
    tuple val(sampleID), path("${sampleID}/${sampleID}_lt150_or_gt175.filtered.bam"),  emit: merged_bam

    script:
    def filter_script = "${params.projectdir}/processes/enrich_features/filter_BAM_based_on_fragment_lenthgs.sh"
    """
    export PATH=/home/dockerUser/samtools/bin:\$PATH
    bash ${filter_script} \\
        -i ${bam} \\
        -s ${sampleID} \\
        -o . \\
        -p ${params.projectdir}
    """
}
