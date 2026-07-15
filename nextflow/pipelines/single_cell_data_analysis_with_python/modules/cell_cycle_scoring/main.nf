process CELL_CYCLE_SCORING {
    tag "${sample}"
    publishDir "${params.outdir}/s5_cell_cycle",               mode: "copy"

    input:
    tuple val(sample), path(h5ad)
    val  use_sctransform
    val  vars_to_regress

    output:
    tuple val(sample), path("*_s5.h5ad"), emit: anndata
    path "cell_cycle_summary.csv",        emit: summary
    path "*.png",                         emit: plots, optional: true

    script:
    """
    cat > run_cell_cycle.py << 'PYEOF'
import argparse

import pandas as pd
import scanpy as sc
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

sc.settings.verbosity = 1

# Same canonical Tirosh et al. (2015) cell-cycle gene sets Seurat ships inside
# its bundled cc.genes object (see src/cc_genes.py for the shared copy).
S_GENES = [
    "MCM5", "PCNA", "TYMS", "FEN1", "MCM2", "MCM4", "RRM1", "UNG", "GINS2",
    "MCM6", "CDCA7", "DTL", "PRIM1", "UHRF1", "MLF1IP", "HELLS", "RFC2",
    "RPA2", "NASP", "RAD51AP1", "GMNN", "WDR76", "SLBP", "CCNE2", "UBR7",
    "POLD3", "MSH2", "ATAD2", "RAD51", "RRM2", "CDC45", "CDC6", "EXO1",
    "TIPIN", "DSCC1", "BLM", "CASP8AP2", "USP1", "CLSPN", "POLA1", "CHAF1B",
    "BRIP1", "E2F8",
]
G2M_GENES = [
    "HMGB2", "CDK1", "NUSAP1", "UBE2C", "BIRC5", "TPX2", "TOP2A", "NDC80",
    "CKS2", "NUF2", "CKS1B", "MKI67", "TMPO", "CENPF", "TACC3", "FAM64A",
    "SMC4", "CCNB2", "CKAP2L", "CKAP2", "AURKB", "BUB1", "KIF11", "ANP32E",
    "TUBB4B", "GTSE1", "KIF20B", "HJURP", "CDCA3", "HN1", "CDC20", "TTK",
    "CDC25C", "KIF2C", "RANGAP1", "NCAPD2", "DLGAP5", "CDCA2", "CDCA8",
    "ECT2", "KIF23", "HMMR", "AURKA", "PSRC1", "ANLN", "LBR", "CKAP5",
    "CENPE", "CTCF", "NEK2", "G2E3", "GAS2L3", "CBX5", "CENPA",
]


def match_case_insensitive(candidates, all_genes):
    lookup = {g.upper(): g for g in all_genes}
    return [lookup[c.upper()] for c in candidates if c.upper() in lookup]


p = argparse.ArgumentParser()
p.add_argument("--h5ad",             type=str)
p.add_argument("--sample",           type=str, default="sample")
p.add_argument("--use_sctransform",  type=str, default="false")
p.add_argument("--vars_to_regress",  type=str, default="percent.mt")
opt = p.parse_args()

adata = sc.read_h5ad(opt.h5ad)
use_sctransform = opt.use_sctransform.lower() == "true"
vars_to_regress = [v.strip() for v in opt.vars_to_regress.split(",")]
# translate Seurat-style obs names (percent.mt) to scanpy-style (percent_mt)
vars_to_regress = [v.replace(".", "_") for v in vars_to_regress]


def s5_preprocess_before_cc_scoring(adata, use_sctransform, vars_to_regress, sample_name):
    # ── QC metrics (recalculate in case not present) ────────────────────────
    adata.var["mt"]   = adata.var_names.str.match(r"^mt-|^MT-")
    adata.var["ribo"] = adata.var_names.str.match(r"^Rpl|^Rps|^RPL|^RPS")
    sc.pp.calculate_qc_metrics(adata, qc_vars=["mt", "ribo"], inplace=True, percent_top=None)
    adata.obs.rename(columns={"pct_counts_mt": "percent_mt", "pct_counts_ribo": "percent_ribo"},
                      inplace=True)
    exclude_genes = adata.var_names[adata.var["mt"] | adata.var["ribo"]]
    adata.obs["percent_exclude"] = (
        adata[:, exclude_genes].X.sum(axis=1).A1 / adata.X.sum(axis=1).A1 * 100
        if hasattr(adata.X, "toarray") else
        adata[:, exclude_genes].X.sum(axis=1) / adata.X.sum(axis=1) * 100
    )

    # ── Normalisation / scaling ──────────────────────────────────────────────
    if use_sctransform:
        # Closest established Python analogue of Seurat::SCTransform: Pearson
        # residual normalisation (Lause/Kobak/Berens 2021 showed this is
        # statistically equivalent to SCTransform's regularised NB model).
        sc.experimental.pp.normalize_pearson_residuals(adata)
        sc.pp.highly_variable_genes(adata, flavor="seurat_v3", n_top_genes=2000, layer=None)
    else:
        sc.pp.normalize_total(adata, target_sum=1e4)
        sc.pp.log1p(adata)
        sc.pp.highly_variable_genes(adata, flavor="seurat")
        sc.pp.scale(adata)

    # ── Match cc genes to this dataset (case-insensitive) ───────────────────
    all_genes = adata.var_names.tolist()
    s_genes   = match_case_insensitive(S_GENES, all_genes)
    g2m_genes = match_case_insensitive(G2M_GENES, all_genes)
    print(f"Cell cycle genes found — S: {len(s_genes)}, G2M: {len(g2m_genes)}")

    # ── Score cell cycle (mirrors Seurat::CellCycleScoring) ─────────────────
    sc.tl.score_genes_cell_cycle(adata, s_genes=s_genes, g2m_genes=g2m_genes)
    return adata


adata = s5_preprocess_before_cc_scoring(
    adata, use_sctransform=use_sctransform, vars_to_regress=vars_to_regress, sample_name=opt.sample
)

# ── PCA on variable features for plotting ───────────────────────────────────
sc.tl.pca(adata, use_highly_variable=True)

fig, ax = plt.subplots(figsize=(7, 6))
for phase in adata.obs["phase"].unique():
    sel = (adata.obs["phase"] == phase).to_numpy()
    ax.scatter(adata.obsm["X_pca"][sel, 0], adata.obsm["X_pca"][sel, 1], s=4, label=phase)
ax.set_title(f"{opt.sample} — Cell cycle phase (PCA)")
ax.legend()
fig.tight_layout(); fig.savefig("cell_cycle_phase_pca.png", dpi=150); plt.close(fig)

fig, axes = plt.subplots(1, 2, figsize=(10, 5))
for ax, col in zip(axes, ["S_score", "G2M_score"]):
    ax.violinplot(adata.obs[col], showmedians=True)
    ax.set_title(col)
fig.suptitle(f"{opt.sample} — S / G2M scores")
fig.tight_layout(); fig.savefig("cell_cycle_scores_violin.png", dpi=150); plt.close(fig)

# ── Summary table ────────────────────────────────────────────────────────────
phase_tbl = adata.obs.groupby(["name", "phase"]).size().reset_index(name="n_cells")
phase_tbl.columns = ["sample", "phase", "n_cells"]
phase_tbl.to_csv("cell_cycle_summary.csv", index=False)

adata.write_h5ad(f"{opt.sample}_s5.h5ad")
print("Step 5 done.")
PYEOF

    python3 run_cell_cycle.py \\
        --h5ad            "${h5ad}" \\
        --sample          "${sample}" \\
        --use_sctransform "${use_sctransform}" \\
        --vars_to_regress "${vars_to_regress}"
    """
}
