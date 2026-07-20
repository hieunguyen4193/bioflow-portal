// Combine all samples belonging to the same subject into one AIRR table.
// Clonal clustering (Change-O) and diversity/lineage analysis (Alakazam/SHazaM/
// dowser) are conventionally run per subject so that lineages spanning
// multiple samples of the same individual are not split apart.
process COMBINE_SUBJECT {
    tag "${subject}"
    publishDir "${params.outdir}/s2b_combined_by_subject/${subject}", mode: 'copy'

    input:
    tuple val(subject), val(sample_ids), path(igh_tsvs)

    output:
    tuple val(subject), path("${subject}_combined_IGH.tsv"), emit: combined

    script:
    """
    python3 - <<'PYEOF'
import csv

files = "${igh_tsvs.join(',')}".split(',')
out_path = "${subject}_combined_IGH.tsv"

writer = None
out_fh = open(out_path, "w", newline="")
for f in files:
    with open(f, newline="") as fh:
        reader = csv.reader(fh, delimiter="\\t")
        header = next(reader)
        if writer is None:
            writer = csv.writer(out_fh, delimiter="\\t")
            writer.writerow(header)
        for row in reader:
            writer.writerow(row)
out_fh.close()
PYEOF
    """
}
