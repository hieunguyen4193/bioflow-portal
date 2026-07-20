// Step 5 — Alpha diversity of the clonotype repertoire per sample.
process DIVERSITY {
    publishDir "${params.outdir}/s5_diversity", mode: 'copy'

    input:
    path adata_h5ad
    val metric

    output:
    path "diversity.h5ad",         emit: adata
    path "diversity_summary.tsv",  emit: summary
    path "diversity.png",          emit: plot

    script:
    """
    cat > run_diversity.py << 'PYEOF'
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

ir.tl.alpha_diversity(adata, groupby="sample_id", target_col="clone_id", metric=metric)

key = "clone_id_alpha_diversity"
if key in adata.uns:
    adata.uns[key].to_csv("diversity_summary.tsv", sep="\\t")
else:
    with open("diversity_summary.tsv", "w") as f:
        f.write(f"# alpha diversity result not found under adata.uns['{key}']\\n")

try:
    ax = ir.pl.alpha_diversity(adata, groupby="sample_id", target_col="clone_id", metric=metric)
    ax.figure.savefig("diversity.png", dpi=150, bbox_inches="tight")
except Exception as e:
    print(f"Falling back to placeholder diversity plot: {e}")
    placeholder_png("diversity.png", f"diversity plot unavailable:\\n{e}")

adata.write_h5ad("diversity.h5ad")
PYEOF

    python3 run_diversity.py
    """
}
