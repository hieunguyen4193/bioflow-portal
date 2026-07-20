// Step 6 — V/J gene usage per subject, heavy (IGH) and light (IGK/IGL)
// chains separately.
process GENE_USAGE {
    tag "${subject}"
    publishDir "${params.outdir}/s6_gene_usage/${subject}", mode: 'copy'

    input:
    tuple val(subject), path(clones_tsv)

    output:
    tuple val(subject), path("${subject}_v_gene_usage.tsv"), emit: v_usage
    tuple val(subject), path("${subject}_v_gene_usage.png"), emit: plot

    script:
    """
    cat > run_gene_usage.py << 'PYEOF'
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd

df = pd.read_csv("${clones_tsv}", sep="\\t")

locus_col = "locus" if "locus" in df.columns else None
v_col     = "v_call" if "v_call" in df.columns else None

if v_col is None:
    with open("${subject}_v_gene_usage.tsv", "w") as f:
        f.write("# v_call column not found\\n")
    fig, ax = plt.subplots(figsize=(6, 3))
    ax.text(0.5, 0.5, "v_call column not found", ha="center", va="center")
    ax.axis("off")
    fig.savefig("${subject}_v_gene_usage.png", dpi=150, bbox_inches="tight")
else:
    group_cols = [locus_col, v_col] if locus_col else [v_col]
    counts = df.groupby(group_cols).size().reset_index(name="n_contigs")
    counts = counts.sort_values("n_contigs", ascending=False)
    counts.to_csv("${subject}_v_gene_usage.tsv", sep="\\t", index=False)

    top = counts.head(30)
    fig, ax = plt.subplots(figsize=(9, 5))
    labels = top[v_col].astype(str) if not locus_col else (top[locus_col].astype(str) + ":" + top[v_col].astype(str))
    ax.bar(labels, top["n_contigs"], color="darkorange")
    ax.set_xticklabels(labels, rotation=90, fontsize=6)
    ax.set_ylabel("Number of contigs")
    ax.set_title("${subject}: V gene usage")
    fig.tight_layout()
    fig.savefig("${subject}_v_gene_usage.png", dpi=150, bbox_inches="tight")
PYEOF

    python3 run_gene_usage.py
    """
}
