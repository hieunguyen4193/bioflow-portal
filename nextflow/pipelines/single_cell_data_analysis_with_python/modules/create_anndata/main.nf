process CREATE_ANNDATA {
    tag "${sample}"
    publishDir "${params.outdir}/s1_scanpy",               mode: "copy"

    input:
    tuple val(sample), path(barcodes), path(features), path(matrix)
    val  min_cells
    val  min_features
    val  max_features
    val  max_mt_pct
    val  remove_tcr_genes

    output:
    tuple val(sample), path("*_s1.h5ad"), emit: anndata
    path "*.png",                         emit: plots
    path "qc_stats.csv",                  emit: qc_table

    script:
    """
    # Build a 10x-mtx-compatible directory from staged files
    mkdir -p tenx_input
    ln -sf "\$(realpath ${barcodes})" tenx_input/barcodes.tsv.gz
    ln -sf "\$(realpath ${features})" tenx_input/features.tsv.gz
    ln -sf "\$(realpath ${matrix})"   tenx_input/matrix.mtx.gz

    cat > run_create_anndata.py << 'PYEOF'
import argparse
import re

import numpy as np
import pandas as pd
import scanpy as sc
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

sc.settings.verbosity = 1

p = argparse.ArgumentParser()
p.add_argument("--tenx_dir",         type=str)
p.add_argument("--sample",           type=str, default="sample")
p.add_argument("--min_cells",        type=int, default=3)
p.add_argument("--min_features",     type=int, default=200)
p.add_argument("--max_features",     type=int, default=5000)
p.add_argument("--max_mt_pct",       type=float, default=20)
p.add_argument("--remove_TCR_genes", type=str, default="false")
opt = p.parse_args()

remove_tcr = opt.remove_TCR_genes.lower() == "true"

# ── Load data (mirrors Seurat::Read10X) ────────────────────────────────────
adata = sc.read_10x_mtx(opt.tenx_dir, var_names="gene_symbols", gex_only=False, cache=False)
adata.var_names_make_unique()

# ── Detect CITE-seq (Antibody Capture feature type) ─────────────────────────
is_multimodal = "feature_types" in adata.var.columns and adata.var["feature_types"].nunique() > 1
if is_multimodal:
    print("CITE-seq detected:", adata.var["feature_types"].unique().tolist())
    adt_mask = adata.var["feature_types"] != "Gene Expression"
    adata_adt = adata[:, adt_mask].copy()
    adata = adata[:, ~adt_mask].copy()
else:
    print("RNA-only data detected.")

# ── Remove TCR genes ─────────────────────────────────────────────────────────
if remove_tcr:
    keep = ~adata.var_names.str.match(r"^TR[ABGD][VDJ]")
    print(f"Removing {(~keep).sum()} TCR genes.")
    adata = adata[:, keep].copy()

adata.obs["name"] = opt.sample
adata.uns["sample_name"] = opt.sample

# ── min.cells / min.features (mirrors Seurat::CreateSeuratObject) ──────────
sc.pp.filter_genes(adata, min_cells=opt.min_cells)
sc.pp.filter_cells(adata, min_genes=opt.min_features)

# ── ADT assay ────────────────────────────────────────────────────────────────
if is_multimodal:
    shared_cells = adata.obs_names.intersection(adata_adt.obs_names)
    adata = adata[shared_cells].copy()
    adata_adt = adata_adt[shared_cells].copy()
    adata.obsm["ADT"] = adata_adt.X.toarray() if hasattr(adata_adt.X, "toarray") else adata_adt.X
    adata.uns["adt_var_names"] = list(adata_adt.var_names)
    print(f"ADT assay added: {adata_adt.n_vars} markers.")

# ── QC metrics ───────────────────────────────────────────────────────────────
adata.var["mt"] = adata.var_names.str.match(r"^MT-|^mt-")
sc.pp.calculate_qc_metrics(adata, qc_vars=["mt"], inplace=True, percent_top=None)
adata.obs.rename(columns={"pct_counts_mt": "percent_mt"}, inplace=True)

fig, axes = plt.subplots(1, 3, figsize=(12, 5))
for ax, col in zip(axes, ["n_genes_by_counts", "total_counts", "percent_mt"]):
    ax.violinplot(adata.obs[col], showmeans=False, showmedians=True)
    ax.set_title(col)
plt.tight_layout()
fig.savefig("qc_violin_prefilter.png", dpi=150)
plt.close(fig)

fig, ax = plt.subplots(figsize=(6, 5))
ax.scatter(adata.obs["total_counts"], adata.obs["n_genes_by_counts"], s=4, alpha=0.4)
ax.set_xlabel("nCount_RNA"); ax.set_ylabel("nFeature_RNA")
fig.savefig("qc_scatter.png", dpi=150)
plt.close(fig)

# ── Filter cells (min/max features, max % MT) ───────────────────────────────
cells_before = adata.n_obs
adata = adata[
    (adata.obs["n_genes_by_counts"] > opt.min_features) &
    (adata.obs["n_genes_by_counts"] < opt.max_features) &
    (adata.obs["percent_mt"] < opt.max_mt_pct)
].copy()

fig, axes = plt.subplots(1, 3, figsize=(12, 5))
for ax, col in zip(axes, ["n_genes_by_counts", "total_counts", "percent_mt"]):
    ax.violinplot(adata.obs[col], showmeans=False, showmedians=True)
    ax.set_title(col)
plt.tight_layout()
fig.savefig("qc_violin_postfilter.png", dpi=150)
plt.close(fig)

# ── Extra QC metrics + plots (mirrors the ggplot "all.QC" list in misc) ─────
adata.var["ribo"] = adata.var_names.str.match(r"^RP[SL]|^Rp[sl]")
sc.pp.calculate_qc_metrics(adata, qc_vars=["ribo"], inplace=True, percent_top=None)
adata.obs.rename(columns={"pct_counts_ribo": "percent_ribo"}, inplace=True)

qc_plot_files = []

fig, ax = plt.subplots(figsize=(5, 4))
adata.obs["name"].value_counts().plot(kind="bar", ax=ax)
ax.set_title("Number of cells in each dataset")
fig.tight_layout(); fig.savefig("qc_cell_counts.png", dpi=150); plt.close(fig)
qc_plot_files.append("qc_cell_counts.png")

fig, ax = plt.subplots(figsize=(6, 4))
for name, grp in adata.obs.groupby("name"):
    ax.hist(np.log10(grp["total_counts"] + 1), bins=40, alpha=0.4, label=name, density=True)
ax.axvline(np.log10(500), color="red")
ax.set_xlabel("log10(nCount_RNA)"); ax.set_ylabel("Cell density")
ax.set_title("Distribution of read depths in each sample"); ax.legend()
fig.tight_layout(); fig.savefig("qc_ncount_distribution.png", dpi=150); plt.close(fig)
qc_plot_files.append("qc_ncount_distribution.png")

fig, ax = plt.subplots(figsize=(6, 4))
for name, grp in adata.obs.groupby("name"):
    ax.hist(np.log10(grp["n_genes_by_counts"] + 1), bins=40, alpha=0.4, label=name, density=True)
ax.axvline(np.log10(1000), color="red")
ax.set_xlabel("log10(nFeature_RNA)"); ax.set_ylabel("Cell density")
ax.set_title("Distribution of number of detected genes in each sample"); ax.legend()
fig.tight_layout(); fig.savefig("qc_nfeature_distribution.png", dpi=150); plt.close(fig)
qc_plot_files.append("qc_nfeature_distribution.png")

fig, ax = plt.subplots(figsize=(6, 5))
sca = ax.scatter(adata.obs["total_counts"], adata.obs["n_genes_by_counts"],
                  c=adata.obs["percent_mt"], cmap="Greys", s=4)
ax.set_xscale("log"); ax.set_yscale("log")
ax.set_xlabel("nCount_RNA"); ax.set_ylabel("nFeature_RNA")
ax.set_title("nCount_RNA vs. nFeature_RNA, colored by % Mitochondrial genes")
fig.colorbar(sca, ax=ax)
fig.tight_layout(); fig.savefig("qc_scatter_mt.png", dpi=150); plt.close(fig)
qc_plot_files.append("qc_scatter_mt.png")

fig, ax = plt.subplots(figsize=(6, 5))
sca = ax.scatter(adata.obs["total_counts"], adata.obs["n_genes_by_counts"],
                  c=adata.obs["percent_ribo"], cmap="Greys", s=4)
ax.set_xscale("log"); ax.set_yscale("log")
ax.set_xlabel("nCount_RNA"); ax.set_ylabel("nFeature_RNA")
ax.set_title("nCount_RNA vs. nFeature_RNA, colored by % Ribosomal genes")
fig.colorbar(sca, ax=ax)
fig.tight_layout(); fig.savefig("qc_scatter_ribo.png", dpi=150); plt.close(fig)
qc_plot_files.append("qc_scatter_ribo.png")

adata.obs["log10GenesPerUMI"] = (
    np.log10(adata.obs["n_genes_by_counts"]) / np.log10(adata.obs["total_counts"])
)
fig, ax = plt.subplots(figsize=(6, 4))
for name, grp in adata.obs.groupby("name"):
    ax.hist(grp["log10GenesPerUMI"], bins=40, alpha=0.4, label=name, density=True)
ax.axvline(0.8, color="black")
ax.set_title("Complexity: log10(nFeature_RNA) / log10(nCount_RNA)"); ax.legend()
fig.tight_layout(); fig.savefig("qc_complexity.png", dpi=150); plt.close(fig)
qc_plot_files.append("qc_complexity.png")

adata.uns["qc_plot_files"] = qc_plot_files

# ── QC summary ───────────────────────────────────────────────────────────────
pd.DataFrame([{
    "sample":          opt.sample,
    "multimodal":      is_multimodal,
    "cells_raw":       cells_before,
    "cells_filtered":  adata.n_obs,
    "median_features": float(np.median(adata.obs["n_genes_by_counts"])),
    "median_counts":   float(np.median(adata.obs["total_counts"])),
    "median_pct_mt":   float(np.median(adata.obs["percent_mt"])),
}]).to_csv("qc_stats.csv", index=False)

adata.write_h5ad(f"{opt.sample}_s1.h5ad")
print(f"Step 1 done. Cells retained: {adata.n_obs} / {cells_before}")
PYEOF

    python3 run_create_anndata.py \\
        --tenx_dir         tenx_input \\
        --sample           "${sample}" \\
        --min_cells        "${min_cells ?: 3}" \\
        --min_features     "${min_features ?: 200}" \\
        --max_features     "${max_features ?: 5000}" \\
        --max_mt_pct       "${max_mt_pct ?: 20}" \\
        --remove_TCR_genes "${remove_tcr_genes ?: false}"
    """
}
