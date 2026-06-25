// Filter fragments by nucleosome distance range from a FLEN_EM_ND.tsv file.
// Requires the FLEN_EM_ND.tsv produced by the bulk_features process.
process ENRICH_FILTER_ND {
    tag "${sampleID}"
    publishDir "${params.outdir}/enrich_filter_nd/${sampleID}", mode: 'copy'

    input:
    tuple val(sampleID), path(flen_em_nd_tsv)

    output:
    tuple val(sampleID), path("${sampleID}.filteredND_${params.nd_min}_${params.nd_max}.tsv"), emit: filtered_tsv

    script:
    def filter_script = "${params.projectdir}/processes/enrich_features/filter_fragments_based_on_nucleosome_distance.sh"
    """
    bash ${filter_script} \\
        -i ${flen_em_nd_tsv} \\
        -s ${sampleID} \\
        -o . \\
        -f ${params.nd_min} \\
        -c ${params.nd_max}
    """
}
