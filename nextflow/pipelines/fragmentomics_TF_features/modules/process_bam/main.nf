// Step 01 — preprocess BAM: sort/index, split by fragment size, convert to BEDPE, genome coverage
process PROCESS_BAM {
    tag "${sampleID}"
    publishDir { "${params.outdir}/step01_process_bam/${sampleID}" }, mode: 'copy', enabled: params.publish_intermediates != "false"

    input:
    tuple val(sampleID), path(bam_file)

    output:
    tuple val(sampleID), path("${sampleID}.preprocessed.bam"),                                                                                                                                              emit: preprocessed_bam
    tuple val(sampleID), path("${sampleID}.preprocessed.bam.bai"),                                                                                                                                          emit: preprocessed_bai
    tuple val(sampleID), path("${sampleID}.preprocessed_splitChroms"),                                                                                                                                      emit: split_chroms
    tuple val(sampleID), path("${sampleID}.preprocessed_region_Full_fraglen_${params.min_flen}_${params.max_flen}.sorted.bed.gz"), path("${sampleID}.preprocessed_region_Full_fraglen_${params.min_flen}_${params.max_flen}.sorted.bed.gz.tbi"), emit: frag
    tuple val(sampleID), path("${sampleID}.avgGenomeCov.tsv"),                                                                                                                                              emit: genomecov
    tuple val(sampleID), path("${sampleID}.preprocessed_${params.short_lower}_${params.short_upper}.short.bam"), path("${sampleID}.preprocessed_${params.short_lower}_${params.short_upper}.short.bam.bai"), emit: short_bam
    tuple val(sampleID), path("${sampleID}.preprocessed_${params.long_lower}_${params.long_upper}.long.bam"),   path("${sampleID}.preprocessed_${params.long_lower}_${params.long_upper}.long.bam.bai"),   emit: long_bam

    script:
    def process_script = "${params.projectdir}/processes/generate_TFBS_features/01_process_BAM_files.sh"
    def prep_id        = "${sampleID}.preprocessed"
    """
    export PATH=/home/dockerUser/samtools/bin:/home/dockerUser/miniconda3/bin:/home/dockerUser/miniconda3/condabin:/home/dockerUser/bedtools2/bin:\$PATH
    export RESOURCE_DIR="${params.resource_dir}"

    mkdir -p workdir
    bash ${process_script} \\
        -i ${bam_file} \\
        -s ${sampleID} \\
        -o workdir \\
        -p ${params.projectdir} \\
        -n ${params.nthreads} \\
        -q ${params.short_lower} \\
        -w ${params.short_upper} \\
        -e ${params.long_lower} \\
        -r ${params.long_upper} \\
        -f ${params.min_flen} \\
        -x ${params.max_flen} \\
        -m ${params.markdup}

    # Promote key outputs to the Nextflow working directory for capture
    OUTBASE="workdir/OUTPUT/01_processed_BAM_files/${sampleID}"

    cp \${OUTBASE}/${prep_id}.bam                                                                                     ./
    cp \${OUTBASE}/${prep_id}.bam.bai                                                                                 ./
    cp -r \${OUTBASE}/${prep_id}_splitChroms                                                                          ./
    cp \${OUTBASE}/${prep_id}_region_Full_fraglen_${params.min_flen}_${params.max_flen}.sorted.bed.gz                 ./
    cp \${OUTBASE}/${prep_id}_region_Full_fraglen_${params.min_flen}_${params.max_flen}.sorted.bed.gz.tbi             ./
    cp \${OUTBASE}/${sampleID}.avgGenomeCov.tsv                                                                       ./
    cp \${OUTBASE}/${prep_id}_${params.short_lower}_${params.short_upper}.short.bam                                   ./
    cp \${OUTBASE}/${prep_id}_${params.short_lower}_${params.short_upper}.short.bam.bai                               ./
    cp \${OUTBASE}/${prep_id}_${params.long_lower}_${params.long_upper}.long.bam                                      ./
    cp \${OUTBASE}/${prep_id}_${params.long_lower}_${params.long_upper}.long.bam.bai                                  ./
    """
}
