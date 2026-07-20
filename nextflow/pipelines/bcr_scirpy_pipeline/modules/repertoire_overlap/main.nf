// Step 6 (optional) — Pairwise repertoire overlap between samples.
// Gracefully no-ops (writes a placeholder) when fewer than 2 samples are present.
process REPERTOIRE_OVERLAP {
    publishDir "${params.outdir}/s6_repertoire_overlap", mode: 'copy'

    input:
    path adata_h5ad
    val metric

    output:
    path "repertoire_overlap.tsv",  emit: summary
    path "repertoire_overlap.png",  emit: plot

    script:
    """
    cat > run_overlap.py << 'PYEOF'
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import scanpy as sc
import scirpy as ir

def placeholder_png(path, message):
    fig, ax = plt.subplots(figsize=(6, 3))
    ax.text(0.5, 0.5, message, ha="center", va="center", wrap=True)
    ax.axis("off")
    fig.savefig(path, dpi=150, bbox_inches="tight")

adata = sc.read_h5ad("${adata_h5ad}")
metric = "${metric}"

n_samples = adata.obs["sample_id"].nunique()
if n_samples < 2:
    with open("repertoire_overlap.tsv", "w") as f:
        f.write(f"# only {n_samples} sample(s) present; repertoire overlap needs >= 2\\n")
    placeholder_png("repertoire_overlap.png", f"Only {n_samples} sample(s) present;\\nrepertoire overlap needs >= 2")
else:
    try:
        ax = ir.pl.repertoire_overlap(adata, groupby="sample_id", target_col="clone_id", overlap_measure=metric)
        ax.figure.savefig("repertoire_overlap.png", dpi=150, bbox_inches="tight")
    except Exception as e:
        print(f"Falling back to placeholder repertoire_overlap plot: {e}")
        placeholder_png("repertoire_overlap.png", f"repertoire_overlap plot unavailable:\\n{e}")

    key = "sample_id_overlap"
    if key in adata.uns and hasattr(adata.uns[key], "to_csv"):
        adata.uns[key].to_csv("repertoire_overlap.tsv", sep="\\t")
    else:
        df = ir.tl.repertoire_overlap(adata, groupby="sample_id", target_col="clone_id", overlap_measure=metric)
        if hasattr(df, "to_csv"):
            df.to_csv("repertoire_overlap.tsv", sep="\\t")
        else:
            with open("repertoire_overlap.tsv", "w") as f:
                f.write("# repertoire overlap table unavailable for this scirpy version\\n")
PYEOF

    python3 run_overlap.py
    """
}
