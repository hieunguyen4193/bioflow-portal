// Step 2 — Chain QC (scirpy chain_qc: receptor_type / receptor_subtype /
// chain_pairing) then keep BCR cells only, optionally dropping multichain
// and/or unpaired cells.
process CHAIN_QC_FILTER {
    publishDir "${params.outdir}/s2_chain_qc_filter", mode: 'copy'

    input:
    path adata_h5ad
    val remove_multichain
    val require_paired

    output:
    path "filtered.h5ad",         emit: adata
    path "chain_qc_summary.tsv",  emit: summary
    path "chain_pairing.png",     emit: plot

    script:
    """
    cat > run_chain_qc.py << 'PYEOF'
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

ir.pp.index_chains(adata)
ir.tl.chain_qc(adata)

summary = adata.obs["chain_pairing"].value_counts().reset_index()
summary.columns = ["chain_pairing", "n_cells"]
summary.to_csv("chain_qc_summary.tsv", sep="\\t", index=False)

try:
    ax = ir.pl.group_abundance(adata, groupby="chain_pairing", target_col="sample_id")
    ax.figure.savefig("chain_pairing.png", dpi=150, bbox_inches="tight")
except Exception as e:
    print(f"Falling back to placeholder chain_pairing plot: {e}")
    placeholder_png("chain_pairing.png", f"chain_pairing plot unavailable:\\n{e}")

remove_multichain = "${remove_multichain}".strip().lower() == "true"
require_paired    = "${require_paired}".strip().lower() == "true"

mask = adata.obs["receptor_type"] == "BCR"
if remove_multichain:
    mask &= adata.obs["chain_pairing"] != "multichain"
if require_paired:
    mask &= adata.obs["chain_pairing"].isin(["single pair", "extra VJ", "extra VDJ"])

n_before = adata.n_obs
adata = adata[mask].copy()
print(f"Kept {adata.n_obs} / {n_before} cells after chain QC filtering.")

adata.write_h5ad("filtered.h5ad")
PYEOF

    python3 run_chain_qc.py
    """
}
