// Step 02 — generate chromosome-level features from splitChroms directory
process CHROMOSOME_FEATURES {
    tag "${sampleID}"
    publishDir "${params.outdir}/step02_chromosome_features", mode: 'copy'

    input:
    tuple val(sampleID), path(split_chroms_dir)

    output:
    tuple val(sampleID), path("${sampleID}.preprocessed_std_avg_shannon.tsv"), emit: chrom_features

    script:
    def chrom_script = "${params.projectdir}/processes/generate_TFBS_features/02_generate_chromosome_features.sh"
    """
    export PATH=/home/dockerUser/samtools/bin:/home/dockerUser/miniconda3/bin:/home/dockerUser/miniconda3/condabin:/home/dockerUser/bedtools2/bin:\$PATH
    mkdir -p workdir
    bash ${chrom_script} \\
        -i ${split_chroms_dir} \\
        -s ${sampleID}.preprocessed \\
        -o workdir \\
        -p ${params.projectdir}

    cp workdir/02_chromosome_features/${sampleID}.preprocessed_std_avg_shannon.tsv ./
    """
}
