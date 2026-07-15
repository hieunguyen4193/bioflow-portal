process FILTER_CELLS {
    tag "${sample}"
    publishDir "${params.outdir}/s3_filter",               mode: "copy"

    input:
    tuple val(sample), path(h5ad)
    val  nFeatureRNA_floor
    val  nFeatureRNA_ceiling
    val  nCountRNA_floor
    val  nCountRNA_ceiling
    val  pct_mito_floor
    val  pct_mito_ceiling
    val  pct_ribo_floor
    val  pct_ribo_ceiling
    val  ambientRNA_thres
    val  log10GenesPerUMI_thres

    output:
    tuple val(sample), path("*_s3.h5ad"), emit: anndata
    path "qc_filter_stats.csv",           emit: qc_table
    path "*.png",                         emit: plots, optional: true

    script:
    def args = [
        "--nFeatureRNA_floor":       nFeatureRNA_floor,
        "--nFeatureRNA_ceiling":     nFeatureRNA_ceiling,
        "--nCountRNA_floor":         nCountRNA_floor,
        "--nCountRNA_ceiling":       nCountRNA_ceiling,
        "--pct_mito_floor":          pct_mito_floor,
        "--pct_mito_ceiling":        pct_mito_ceiling,
        "--pct_ribo_floor":          pct_ribo_floor,
        "--pct_ribo_ceiling":        pct_ribo_ceiling,
        "--ambientRNA_thres":        ambientRNA_thres,
        "--log10GenesPerUMI_thres":  log10GenesPerUMI_thres,
    ].findAll { k, v -> v != "null" && v != "" }
     .collect { k, v -> "$k $v" }
     .join(" \\\n        ")

    """
    cat > run_filter.py << 'PYEOF'
import argparse

import numpy as np
import pandas as pd
import scanpy as sc
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

sc.settings.verbosity = 1


def _opt_float(v):
    return None if v is None else float(v)


p = argparse.ArgumentParser()
p.add_argument("--h5ad",                    type=str)
p.add_argument("--sample",                  type=str, default="sample")
p.add_argument("--nFeatureRNA_floor",       type=_opt_float, default=None)
p.add_argument("--nFeatureRNA_ceiling",     type=_opt_float, default=None)
p.add_argument("--nCountRNA_floor",         type=_opt_float, default=None)
p.add_argument("--nCountRNA_ceiling",       type=_opt_float, default=None)
p.add_argument("--pct_mito_floor",          type=_opt_float, default=None)
p.add_argument("--pct_mito_ceiling",        type=_opt_float, default=None)
p.add_argument("--pct_ribo_floor",          type=_opt_float, default=None)
p.add_argument("--pct_ribo_ceiling",        type=_opt_float, default=None)
p.add_argument("--ambientRNA_thres",        type=_opt_float, default=None)
p.add_argument("--log10GenesPerUMI_thres",  type=_opt_float, default=None)
opt = p.parse_args()

adata = sc.read_h5ad(opt.h5ad)
cells_before = adata.n_obs

# ── Add ribosomal % if not already present ─────────────────────────────────
if "percent_ribo" not in adata.obs.columns:
    adata.var["ribo"] = adata.var_names.str.match(r"^RP[SL]")
    sc.pp.calculate_qc_metrics(adata, qc_vars=["ribo"], inplace=True, percent_top=None)
    adata.obs.rename(columns={"pct_counts_ribo": "percent_ribo"}, inplace=True)

# ── Add log10GenesPerUMI if not already present ────────────────────────────
if "log10GenesPerUMI" not in adata.obs.columns:
    adata.obs["log10GenesPerUMI"] = (
        np.log10(adata.obs["n_genes_by_counts"]) / np.log10(adata.obs["total_counts"])
    )


def s3_filter(adata, opt):
    mask = np.ones(adata.n_obs, dtype=bool)
    obs = adata.obs
    if opt.nFeatureRNA_floor is not None:
        mask &= (obs["n_genes_by_counts"] > opt.nFeatureRNA_floor).to_numpy()
    if opt.nFeatureRNA_ceiling is not None:
        mask &= (obs["n_genes_by_counts"] < opt.nFeatureRNA_ceiling).to_numpy()
    if opt.nCountRNA_floor is not None:
        mask &= (obs["total_counts"] > opt.nCountRNA_floor).to_numpy()
    if opt.nCountRNA_ceiling is not None:
        mask &= (obs["total_counts"] < opt.nCountRNA_ceiling).to_numpy()
    if opt.pct_mito_floor is not None:
        mask &= (obs["percent_mt"] > opt.pct_mito_floor).to_numpy()
    if opt.pct_mito_ceiling is not None:
        mask &= (obs["percent_mt"] < opt.pct_mito_ceiling).to_numpy()
    if opt.pct_ribo_floor is not None:
        mask &= (obs["percent_ribo"] > opt.pct_ribo_floor).to_numpy()
    if opt.pct_ribo_ceiling is not None:
        mask &= (obs["percent_ribo"] < opt.pct_ribo_ceiling).to_numpy()
    if opt.ambientRNA_thres is not None and "AmbientRNA" in obs.columns:
        mask &= (obs["AmbientRNA"] < opt.ambientRNA_thres).to_numpy()
    if opt.log10GenesPerUMI_thres is not None:
        mask &= (obs["log10GenesPerUMI"] >= opt.log10GenesPerUMI_thres).to_numpy()
    return adata[mask].copy()


adata = s3_filter(adata, opt)
cells_after = adata.n_obs
print(f"Filtering: {cells_before} -> {cells_after} cells (removed {cells_before - cells_after})")

# ── Post-filter QC violin ──────────────────────────────────────────────────
features_to_plot = [c for c in
                     ["n_genes_by_counts", "total_counts", "percent_mt", "percent_ribo", "log10GenesPerUMI"]
                     if c in adata.obs.columns]
ncol = min(3, len(features_to_plot))
nrow = int(np.ceil(len(features_to_plot) / ncol))
fig, axes = plt.subplots(nrow, ncol, figsize=(4 * ncol, 5 * nrow), squeeze=False)
for i, col in enumerate(features_to_plot):
    ax = axes[i // ncol][i % ncol]
    ax.violinplot(adata.obs[col].dropna(), showmedians=True)
    ax.set_title(col)
fig.tight_layout()
fig.savefig("qc_violin_s3_postfilter.png", dpi=150)
plt.close(fig)

# ── Filter summary ──────────────────────────────────────────────────────────
pd.DataFrame([{
    "sample":                 opt.sample,
    "cells_before":           cells_before,
    "cells_after":            cells_after,
    "cells_removed":          cells_before - cells_after,
    "pct_removed":            round((cells_before - cells_after) / cells_before * 100, 2),
    "nFeatureRNA_floor":      opt.nFeatureRNA_floor,
    "nFeatureRNA_ceiling":    opt.nFeatureRNA_ceiling,
    "nCountRNA_floor":        opt.nCountRNA_floor,
    "nCountRNA_ceiling":      opt.nCountRNA_ceiling,
    "pct_mito_ceiling":       opt.pct_mito_ceiling,
    "pct_ribo_floor":         opt.pct_ribo_floor,
    "ambientRNA_thres":       opt.ambientRNA_thres,
    "log10GenesPerUMI_thres": opt.log10GenesPerUMI_thres,
}]).to_csv("qc_filter_stats.csv", index=False)

adata.write_h5ad(f"{opt.sample}_s3.h5ad")
print("Step 3 done.")
PYEOF

    python3 run_filter.py \\
        --h5ad   "${h5ad}" \\
        --sample "${sample}" \\
        ${args}
    """
}
