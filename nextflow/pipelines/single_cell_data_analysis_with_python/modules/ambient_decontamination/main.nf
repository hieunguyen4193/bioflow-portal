process AMBIENT_DECONTAMINATION {
    tag "${sample} / ${method}"
    publishDir "${params.outdir}/s2_ambient",               mode: "copy"

    input:
    tuple val(sample), path(h5ad)
    val  method

    output:
    tuple val(sample), path("*_s2.h5ad"), emit: anndata
    path "*.png",                         emit: plots, optional: true

    script:
    """
    cat > run_ambient.py << 'PYEOF'
import argparse

import numpy as np
import pandas as pd
import scanpy as sc
from scipy.sparse import csr_matrix, issparse
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

sc.settings.verbosity = 1

p = argparse.ArgumentParser()
p.add_argument("--h5ad",   type=str)
p.add_argument("--method", type=str, default="decontX")
p.add_argument("--sample", type=str, default="sample")
opt = p.parse_args()

adata = sc.read_h5ad(opt.h5ad)


def em_decontx(X_csr, cluster_labels, n_iter=3, newton_iters=5):
    \"\"\"
    Lightweight, pure-Python re-implementation of the decontX model
    (Yang et al. 2020): each cell's observed counts are modelled as a
    mixture of its cluster's "native" expression profile and a shared
    "ambient" background profile, with a per-cell contamination weight c.
    There is no official Python port of Bioconductor's celda::decontX, so
    this EM approximation (clustering -> per-cell contamination fraction
    via Newton-Raphson on the multinomial mixture likelihood -> profile
    refresh) stands in for it. Returns (contamination, corrected_counts).
    \"\"\"
    n_cells, n_genes = X_csr.shape
    n_clusters = int(cluster_labels.max()) + 1
    X_coo = X_csr.tocoo()
    rows, cols, data = X_coo.row, X_coo.col, X_coo.data.astype(np.float64)

    def profiles_from_weights(weights):
        idx = cluster_labels[rows] * n_genes + cols
        flat = np.zeros(n_clusters * n_genes)
        np.add.at(flat, idx, weights)
        mat = flat.reshape(n_clusters, n_genes)
        row_sums = mat.sum(axis=1, keepdims=True)
        row_sums[row_sums == 0] = 1
        return mat / row_sums

    p_z = profiles_from_weights(data)                       # assume c=0 initially
    p_ambient = np.zeros(n_genes)
    np.add.at(p_ambient, cols, data)
    p_ambient = p_ambient / p_ambient.sum()

    c = np.full(n_cells, 0.1)

    for _ in range(n_iter):
        pz_vals = p_z[cluster_labels[rows], cols]
        pa_vals = p_ambient[cols]
        for _ in range(newton_iters):
            c_rows = c[rows]
            denom = np.clip((1 - c_rows) * pz_vals + c_rows * pa_vals, 1e-12, None)
            diff = pa_vals - pz_vals
            f  = np.bincount(rows, weights=data * diff / denom, minlength=n_cells)
            fp = np.bincount(rows, weights=-data * diff ** 2 / denom ** 2, minlength=n_cells)
            fp = np.where(np.abs(fp) < 1e-12, -1e-12, fp)
            c = np.clip(c - f / fp, 0.0, 0.9)

        c_rows = c[rows]
        p_z = profiles_from_weights(data * (1 - c_rows))
        ambient_w = data * c_rows
        p_ambient_new = np.zeros(n_genes)
        np.add.at(p_ambient_new, cols, ambient_w)
        total = p_ambient_new.sum()
        if total > 0:
            p_ambient = p_ambient_new / total

    pz_vals = p_z[cluster_labels[rows], cols]
    pa_vals = p_ambient[cols]
    c_rows = c[rows]
    denom = np.clip((1 - c_rows) * pz_vals + c_rows * pa_vals, 1e-12, None)
    expected_ambient = data * c_rows * pa_vals / denom
    corrected = np.clip(np.round(data - expected_ambient), 0, None)

    X_corrected = csr_matrix((corrected, (rows, cols)), shape=X_csr.shape)
    return c, X_corrected


def s2_ambient_rna_correction(adata, chosen_method, sample_name):
    if chosen_method == "decontX":
        contamination = np.zeros(adata.n_obs)
        clusters      = np.full(adata.n_obs, -1, dtype=int)
        corrected_X   = adata.X.tocsr().copy() if issparse(adata.X) else csr_matrix(adata.X)

        for batch in adata.obs["name"].unique():
            mask = (adata.obs["name"] == batch).values
            sub = adata[mask].copy()

            # cluster within this batch to get "native" profiles, same role
            # as decontX's internal clustering step
            sc.pp.normalize_total(sub, target_sum=1e4)
            sc.pp.log1p(sub)
            sc.pp.highly_variable_genes(sub, n_top_genes=min(2000, sub.n_vars))
            sc.tl.pca(sub, n_comps=min(30, sub.n_vars - 1, sub.n_obs - 1))
            sc.pp.neighbors(sub)
            sc.tl.leiden(sub, key_added="decontX_clusters")
            sc.tl.umap(sub)

            cluster_labels = sub.obs["decontX_clusters"].cat.codes.to_numpy()
            X_raw = adata[mask].X
            X_raw = X_raw.tocsr() if issparse(X_raw) else csr_matrix(X_raw)

            c, X_corr = em_decontx(X_raw, cluster_labels)

            contamination[mask] = c
            clusters[mask] = cluster_labels
            corrected_X[np.where(mask)[0], :] = X_corr

            fig, ax = plt.subplots(figsize=(8, 6))
            for cl in sorted(sub.obs["decontX_clusters"].unique(), key=int):
                sel = sub.obs["decontX_clusters"] == cl
                emb = sub.obsm["X_umap"][sel.values]
                ax.scatter(emb[:, 0], emb[:, 1], s=4, label=str(cl))
            ax.set_title(f"Dim. reduce cluster (decontX_UMAP) — {batch}")
            ax.legend(markerscale=3, fontsize=6, ncol=2)
            fig.tight_layout()
            fig.savefig(f"ambient_cluster_decontX_UMAP_{batch}.png", dpi=150)
            plt.close(fig)

            fig, ax = plt.subplots(figsize=(6, 5))
            ax.hist(c, bins=40)
            ax.set_xlabel("Estimated contamination fraction")
            ax.set_title(f"Contamination: {batch}")
            fig.tight_layout()
            fig.savefig(f"ambient_contamination_{batch}.png", dpi=150)
            plt.close(fig)

        adata.layers["decontXcounts"] = corrected_X
        adata.obs["AmbientRNA"]       = contamination
        adata.obs["decontX_clusters"] = pd.Categorical(clusters.astype(str))

    elif chosen_method == "SoupX":
        # Mirrors the R pipeline exactly: SoupX is not implemented there either.
        raise NotImplementedError("SoupX support is not yet implemented.")
    else:
        raise ValueError(f"chosen_method must be 'decontX' or 'SoupX'. Got: {chosen_method}")

    return adata


adata = s2_ambient_rna_correction(adata, opt.method, opt.sample)

out_h5ad = f"{opt.sample}_s2.h5ad"
adata.write_h5ad(out_h5ad)
print(f"Step 2 done. Saved: {out_h5ad}")
PYEOF

    python3 run_ambient.py \\
        --h5ad   "${h5ad}" \\
        --method "${method}" \\
        --sample "${sample}"
    """
}
