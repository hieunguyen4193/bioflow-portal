// Step 4 — Clonal expansion categories per cell + a per-sample summary plot.
process CLONAL_EXPANSION {
    publishDir "${params.outdir}/s4_clonal_expansion", mode: 'copy'

    input:
    path adata_h5ad

    output:
    path "expanded.h5ad",                emit: adata
    path "clonal_expansion_summary.tsv", emit: summary
    path "clonal_expansion.png",         emit: plot

    script:
    """
    cat > run_clonal_expansion.py << 'PYEOF'
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

ir.tl.clonal_expansion(adata)

summary = adata.obs["clonal_expansion"].value_counts().reset_index()
summary.columns = ["clonal_expansion", "n_cells"]
summary.to_csv("clonal_expansion_summary.tsv", sep="\\t", index=False)

try:
    ax = ir.pl.clonal_expansion(adata, groupby="sample_id", target_col="clone_id")
    ax.figure.savefig("clonal_expansion.png", dpi=150, bbox_inches="tight")
except Exception as e:
    print(f"Falling back to placeholder clonal_expansion plot: {e}")
    placeholder_png("clonal_expansion.png", f"clonal_expansion plot unavailable:\\n{e}")

adata.write_h5ad("expanded.h5ad")
PYEOF

    python3 run_clonal_expansion.py
    """
}
