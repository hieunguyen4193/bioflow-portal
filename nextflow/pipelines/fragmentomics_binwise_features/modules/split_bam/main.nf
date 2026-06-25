// Split a full BAM into short (<= 150 bp) and long (> 150 bp) fragment BAMs.
process SPLIT_BAM {
    tag "${sampleID}"
    publishDir { "${params.outdir}/split_bam/${sampleID}" }, mode: 'copy'

    input:
    tuple val(sampleID), path(full_bam), path(full_bai)

    output:
    tuple val(sampleID),
        path("${sampleID}.short.bam"), path("${sampleID}.short.bam.bai"),
        path("${sampleID}.long.bam"),  path("${sampleID}.long.bam.bai"),
        path(full_bam),                path(full_bai),
        emit: split_bams

    script:
    def cutoff = params.split_cutoff ?: 150
    """
    export PATH=/home/dockerUser/samtools/bin:/home/dockerUser/miniconda3/bin:/home/dockerUser/miniconda3/condabin:\$PATH

    samtools view -h ${full_bam} | \
        awk 'substr(\$0,1,1)=="@" || (\$9 >= 1 && \$9 <= ${cutoff}) || (\$9 <= -1 && \$9 >= -${cutoff})' | \
        samtools view -b | samtools sort > ${sampleID}.short.bam
    samtools index ${sampleID}.short.bam

    samtools view -h ${full_bam} | \
        awk 'substr(\$0,1,1)=="@" || (\$9 > ${cutoff}) || (\$9 < -${cutoff})' | \
        samtools view -b | samtools sort > ${sampleID}.long.bam
    samtools index ${sampleID}.long.bam
    """
}
