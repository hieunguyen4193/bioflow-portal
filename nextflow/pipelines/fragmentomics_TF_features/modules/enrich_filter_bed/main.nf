// Filter a BAM file to only reads overlapping a given BED file (e.g. enriched regions).
process ENRICH_FILTER_BED {
    tag "${sampleID}"
    publishDir "${params.outdir}/enrich_filter_bed", mode: 'copy'

    input:
    tuple val(sampleID), path(bam), path(bai), path(bed_file)

    output:
    tuple val(sampleID), path("${bed_name}/${sampleID}.bam"),     emit: filtered_bam
    tuple val(sampleID), path("${bed_name}/${sampleID}.bam.bai"), emit: filtered_bai

    script:
    def filter_script = "${params.projectdir}/processes/enrich_features/filter_BAM_based_on_BED.sh"
    bed_name          = bed_file.baseName.replaceAll(/\.bed$/, '')
    """
    export PATH=/home/dockerUser/samtools/bin:\$PATH
    bash ${filter_script} \\
        -i ${bam} \\
        -s ${sampleID} \\
        -b ${bed_file} \\
        -o .
    """
}
