// Step 2 — Load the reannotated AIRR table into a Dandelion object and run
// contig QC (ambiguous/chimeric contig filtering, productive-only filtering).
process CONTIG_QC {
    tag "${sample_id}"
    publishDir "${params.outdir}/s2_contig_qc/${sample_id}", mode: 'copy'

    input:
    tuple val(sample_id), val(subject), path(reannotated_tsv), path(contig_annotations)
    val productive_only

    output:
    tuple val(sample_id), val(subject), path("${sample_id}_qc.tsv"), emit: qc_pass
    path "${sample_id}_qc_summary.tsv",                              emit: summary

    script:
    """
    cat > run_contig_qc.py << 'PYEOF'
import pandas as pd
import dandelion as ddl

df = pd.read_csv("${reannotated_tsv}", sep="\\t")
n_before = len(df)

vdj = ddl.Dandelion(df)

productive_only = "${productive_only}".strip().lower() == "true"
vdj = ddl.pp.check_contigs(vdj, productive_only=productive_only)

vdj.data["sample_id"] = "${sample_id}"
vdj.data["subject"]   = "${subject}"

vdj.data.to_csv("${sample_id}_qc.tsv", sep="\\t", index=False)

n_after = len(vdj.data)
with open("${sample_id}_qc_summary.tsv", "w") as f:
    f.write("metric\\tvalue\\n")
    f.write(f"contigs_before\\t{n_before}\\n")
    f.write(f"contigs_after\\t{n_after}\\n")
PYEOF

    python3 run_contig_qc.py
    """
}
