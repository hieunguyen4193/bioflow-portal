// Combine all samples belonging to the same subject into one contig table,
// so clone definition and network construction run per subject (consistent
// with the Immcantation pipeline's convention, avoiding clones/networks that
// spuriously span different individuals).
process COMBINE_SUBJECT {
    tag "${subject}"
    publishDir "${params.outdir}/s2b_combined_by_subject/${subject}", mode: 'copy'

    input:
    tuple val(subject), val(sample_ids), path(qc_tsvs)

    output:
    tuple val(subject), path("${subject}_combined.tsv"), emit: combined

    script:
    """
    python3 - <<'PYEOF'
import pandas as pd

files = "${qc_tsvs.join(',')}".split(',')
combined = pd.concat([pd.read_csv(f, sep="\\t") for f in files], ignore_index=True)
combined.to_csv("${subject}_combined.tsv", sep="\\t", index=False)
PYEOF
    """
}
