// Step 2 — Keep productive/functional sequences only, then split by locus.
// The IGH file feeds clonal clustering (Change-O convention: cluster on the
// heavy chain); the full functional table (all loci) is kept for reporting.
process FILTER_FUNCTIONAL {
    tag "${sample_id}"
    publishDir "${params.outdir}/s2_filter_functional/${sample_id}", mode: 'copy'

    input:
    tuple val(sample_id), val(subject), path(db_pass)

    output:
    tuple val(sample_id), val(subject), path("${sample_id}_functional.tsv"),     emit: functional
    tuple val(sample_id), val(subject), path("${sample_id}_functional_IGH.tsv"), emit: functional_igh, optional: true

    script:
    """
    ParseDb.py select \\
        -d ${db_pass} \\
        -f productive \\
        -u T \\
        --outname ${sample_id}_functional

    mv ${sample_id}_functional_parse-select.tsv ${sample_id}_functional.tsv

    ParseDb.py split \\
        -d ${sample_id}_functional.tsv \\
        -f locus

    if [ -f ${sample_id}_functional_IGH.tsv ]; then
        echo "IGH sequences found."
    else
        echo "No IGH sequences for sample ${sample_id}." >&2
    fi
    """
}
