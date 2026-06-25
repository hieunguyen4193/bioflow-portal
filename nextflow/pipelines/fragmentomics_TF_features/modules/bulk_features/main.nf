// Generate bulk features from a fragment bed.gz file.
// Computes End Motif (EM) and Nucleosome Distance (ND) then builds 2D FLEN/EM/ND features.
process BULK_FEATURES {
    tag "${sampleID}"
    publishDir { "${params.outdir}/bulk_features/${sampleID}" }, mode: 'copy'

    input:
    tuple val(sampleID), path(frag)

    output:
    tuple val(sampleID), path("${sampleID}_bulk_features"),   emit: bulk_features
    tuple val(sampleID), path("${sampleID}_FLEN_EM_ND.tsv"),  emit: flen_em_nd

    script:
    def bulk_script = "${params.projectdir}/processes/generate_bulk_features.sh"
    """
    export PATH=/home/dockerUser/samtools/bin:/home/dockerUser/miniconda3/bin:/home/dockerUser/miniconda3/condabin:/home/dockerUser/bedtools2/bin:\$PATH
    sed 's|/mnt/NFS_190T/DATA_HIEUNGUYEN/resources/preprocessed_resources/TFBS|${params.resource_dir}/TFBS|g; s|/mnt/NFS_190T/DATA_HIEUNGUYEN/resources|${params.resource_dir}|g' ${bulk_script} > patched_bulk.sh
    mkdir -p workdir
    bash patched_bulk.sh \\
        -i ${frag} \\
        -s ${sampleID} \\
        -o workdir \\
        -p ${params.projectdir}

    cp -r workdir/${sampleID}_bulk_features ./
    cp    workdir/${sampleID}_FLEN_EM_ND.tsv ./
    """
}
