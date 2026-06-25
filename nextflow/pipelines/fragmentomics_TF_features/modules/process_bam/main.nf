// Step 01 — preprocess BAM: sort/index, split by fragment size, convert to BEDPE, genome coverage
process PROCESS_BAM {
    tag "${sampleID}"
    publishDir "${params.outdir}/step01_process_bam/${sampleID}", mode: 'copy'

    input:
    tuple val(sampleID), path(bam_file)

    output:
    tuple val(sampleID), path("${sampleID}.preprocessed.bam"),                                      emit: preprocessed_bam
    tuple val(sampleID), path("${sampleID}.preprocessed.bam.bai"),                                  emit: preprocessed_bai
    tuple val(sampleID), path("${sampleID}.preprocessed_splitChroms"),                              emit: split_chroms
    tuple val(sampleID), path("${sampleID}.preprocessed_region_Full_fraglen_${params.min_flen}_${params.max_flen}.sorted.bed.gz"), emit: frag
    tuple val(sampleID), path("${sampleID}.preprocessed.avgGenomeCov.tsv"),                         emit: genomecov

    script:
    def process_script = "${params.projectdir}/processes/generate_TFBS_features/01_process_BAM_files.sh"
    def prep_id        = "${sampleID}.preprocessed"
    """
    export PATH=/home/dockerUser/samtools/bin:\$PATH

    # Run the process script into a local workdir
    mkdir -p workdir
    bash ${process_script} \\
        -i ${bam_file} \\
        -s ${sampleID} \\
        -o workdir \\
        -p ${params.projectdir}

    # Promote key outputs to the Nextflow working directory for capture
    OUTBASE="workdir/OUTPUT/01_processed_BAM_files/${sampleID}"

    cp \${OUTBASE}/${prep_id}.bam                                                         ./
    cp \${OUTBASE}/${prep_id}.bam.bai                                                     ./
    cp -r \${OUTBASE}/${prep_id}_splitChroms                                              ./
    cp \${OUTBASE}/${prep_id}_region_Full_fraglen_${params.min_flen}_${params.max_flen}.sorted.bed.gz ./
    cp \${OUTBASE}/${prep_id}.avgGenomeCov.tsv                                            ./
    """
}
