process DOUBLET_DETECTION {
    tag "${sample}"
    publishDir "${params.outdir}/s4_doublet",               mode: "copy"

    input:
    tuple val(sample), path(h5ad)
    path  doublet_csv
    val   remove_doublet

    output:
    tuple val(sample), path("*_s4.h5ad"), emit: anndata
    path  "doublet_summary.csv",          emit: summary
    path  "*.png",                        emit: plots, optional: true

    script:
    """
    cat > run_doublet.py << 'PYEOF'
import argparse

import numpy as np
import pandas as pd
import scanpy as sc
import scrublet as scr
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

sc.settings.verbosity = 1

p = argparse.ArgumentParser()
p.add_argument("--h5ad",            type=str)
p.add_argument("--sample",          type=str, default="sample")
p.add_argument("--doublet_csv",     type=str)
p.add_argument("--remove_doublet",  type=str, default="false")
opt = p.parse_args()

remove_doublet = opt.remove_doublet.lower() == "true"
adata = sc.read_h5ad(opt.h5ad)


def s4_doublet_detection(adata, path_to_10x_doublet_estimation, remove_doublet, sample_name):
    number_of_cells = adata.obs["name"].value_counts()
    estimation_10x  = pd.read_csv(path_to_10x_doublet_estimation)

    # equivalent of R's approxfun(..., rule = 2) — linear interpolation with
    # constant extrapolation outside the observed range
    def model_recovered(n):
        return np.interp(
            n, estimation_10x["CellsRecovered"], estimation_10x["MultipletRate"] / 100
        )

    doublet_formation_rate = {name: model_recovered(n) for name, n in number_of_cells.items()}
    print("Doublet rates:", {k: round(v, 3) for k, v in doublet_formation_rate.items()})

    classifications = pd.Series(index=adata.obs_names, dtype=object)
    doublet_scores  = pd.Series(index=adata.obs_names, dtype=float)

    for name in adata.obs["name"].unique():
        mask = (adata.obs["name"] == name).values
        sub = adata[mask]
        counts = sub.X.toarray() if hasattr(sub.X, "toarray") else np.asarray(sub.X)

        scrub = scr.Scrublet(counts, expected_doublet_rate=doublet_formation_rate[name])
        scores, predicted = scrub.scrub_doublets(verbose=False)

        classifications.loc[sub.obs_names] = np.where(predicted, "Doublet", "Singlet")
        doublet_scores.loc[sub.obs_names]  = scores

        # quick per-sample embedding purely for the QC plot (mirrors the R
        # module's per-sample NormalizeData -> PCA -> UMAP before DoubletFinder)
        sub_proc = sub.copy()
        sc.pp.normalize_total(sub_proc, target_sum=1e4)
        sc.pp.log1p(sub_proc)
        sc.pp.highly_variable_genes(sub_proc, n_top_genes=min(2000, sub_proc.n_vars))
        sc.tl.pca(sub_proc, n_comps=min(20, sub_proc.n_vars - 1, sub_proc.n_obs - 1))
        sc.pp.neighbors(sub_proc)
        sc.tl.umap(sub_proc)

        fig, ax = plt.subplots(figsize=(7, 6))
        colors = {"Singlet": "#2166AC", "Doublet": "#D6604D"}
        cls = classifications.loc[sub.obs_names].to_numpy()
        for label in ["Singlet", "Doublet"]:
            sel = cls == label
            ax.scatter(sub_proc.obsm["X_umap"][sel, 0], sub_proc.obsm["X_umap"][sel, 1],
                       s=4, c=colors[label], label=label)
        ax.set_title(f"Doublets: {name}")
        ax.legend()
        fig.tight_layout()
        fig.savefig(f"doublet_umap_{name}.png", dpi=150)
        plt.close(fig)

    adata.obs["Doublet_classifications"] = pd.Categorical(
        classifications, categories=["Singlet", "Doublet"]
    )
    adata.obs["doublet_score"] = doublet_scores

    if remove_doublet:
        before = adata.n_obs
        adata = adata[adata.obs["Doublet_classifications"] == "Singlet"].copy()
        print(f"Removed {before - adata.n_obs} doublets ({before} -> {adata.n_obs} cells)")

    return adata


adata = s4_doublet_detection(
    adata,
    path_to_10x_doublet_estimation=opt.doublet_csv,
    remove_doublet=remove_doublet,
    sample_name=opt.sample,
)

summary_df = pd.crosstab(adata.obs["name"], adata.obs["Doublet_classifications"])
summary_df = summary_df.reset_index().rename(columns={"name": "sample"})
summary_df["removed"] = remove_doublet
summary_df.to_csv("doublet_summary.csv", index=False)

adata.write_h5ad(f"{opt.sample}_s4.h5ad")
print("Step 4 done.")
PYEOF

    python3 run_doublet.py \\
        --h5ad           "${h5ad}" \\
        --sample         "${sample}" \\
        --doublet_csv    "${doublet_csv}" \\
        --remove_doublet "${remove_doublet ?: false}"
    """
}
