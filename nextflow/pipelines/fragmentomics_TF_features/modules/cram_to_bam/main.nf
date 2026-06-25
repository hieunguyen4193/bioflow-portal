process CRAM_TO_BAM {
    tag "${sampleID}"
    publishDir "${params.outdir}/step00_cram_to_bam", mode: 'copy'

    input:
    tuple val(sampleID), path(cram_file)

    output:
    tuple val(sampleID), path("${sampleID}.bam"), emit: bam

    script:
    """
    export PATH=/home/dockerUser/samtools/bin:/home/dockerUser/miniconda3/bin:/home/dockerUser/miniconda3/condabin:/home/dockerUser/bedtools2/bin:\$PATH
    samtools view -b -T ${params.resource_dir}/hg19.fa -o ${sampleID}.bam ${cram_file}
    samtools index ${sampleID}.bam
    """
}
