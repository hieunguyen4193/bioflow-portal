process CELL_CYCLE_SCORING_S6 {
    tag "${sample}"
    publishDir "${params.outdir}/s6_cell_cycle_scoring",               mode: "copy"

    input:
    tuple val(sample), path(h5ad)
    val  mode

    output:
    tuple val(sample), path("*_s6.h5ad"), emit: anndata
    path "cell_cycle_s6_summary.csv",     emit: summary
    path "*.png",                         emit: plots, optional: true

    script:
    """
    cat > run_cell_cycle_s6.py << 'PYEOF'
import argparse

import numpy as np
import pandas as pd
import scanpy as sc
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

sc.settings.verbosity = 1

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
p.add_argument("--h5ad",   type=str)
p.add_argument("--sample", type=str, default="sample")
p.add_argument("--mode",   type=str, default="gene_name")
opt = p.parse_args()

adata = sc.read_h5ad(opt.h5ad)


def s6_cell_cycle_scoring(adata, mode, sample_name):
    sc.pp.scale(adata)

    if mode == "gene_name":
        all_genes = adata.var_names.tolist()
        s_genes   = match_case_insensitive(S_GENES, all_genes)
        g2m_genes = match_case_insensitive(G2M_GENES, all_genes)
        print(f"Gene-name mode — S genes: {len(s_genes)}, G2M genes: {len(g2m_genes)}")

    elif mode == "ensembl":
        # Python equivalent of org.Hs.eg.db::mapIds(..., keytype="SYMBOL",
        # column="ENSEMBL"): query MyGene.info for SYMBOL -> ENSEMBL mapping.
        import mygene
        mg = mygene.MyGeneInfo()

        def to_ensembl(symbols):
            res = mg.querymany(symbols, scopes="symbol", fields="ensembl.gene",
                                species="human", verbose=False)
            out = []
            for r in res:
                ens = r.get("ensembl")
                if isinstance(ens, list):
                    ens = ens[0]
                if isinstance(ens, dict) and "gene" in ens:
                    out.append(ens["gene"])
            return out

        s_genes_ensembl   = [g for g in to_ensembl(S_GENES)   if g in adata.var_names]
        g2m_genes_ensembl = [g for g in to_ensembl(G2M_GENES) if g in adata.var_names]
        print(f"Ensembl mode — S genes: {len(s_genes_ensembl)}, G2M genes: {len(g2m_genes_ensembl)}")
        s_genes, g2m_genes = s_genes_ensembl, g2m_genes_ensembl

    else:
        raise ValueError(f"mode must be 'gene_name' or 'ensembl'. Got: {mode}")

    sc.tl.score_genes_cell_cycle(adata, s_genes=s_genes, g2m_genes=g2m_genes)

    # ── Extra scores ─────────────────────────────────────────────────────────
    adata.obs["G1_score"]      = 1 - adata.obs["S_score"] - adata.obs["G2M_score"]
    adata.obs["CC_difference"] = adata.obs["S_score"] - adata.obs["G2M_score"]

    # ── Ensure QC metrics present ────────────────────────────────────────────
    if "percent_mt" not in adata.obs.columns:
        adata.var["mt"] = adata.var_names.str.match(r"^mt-|^MT-")
        sc.pp.calculate_qc_metrics(adata, qc_vars=["mt"], inplace=True, percent_top=None)
        adata.obs.rename(columns={"pct_counts_mt": "percent_mt"}, inplace=True)
    if "percent_ribo" not in adata.obs.columns:
        adata.var["ribo"] = adata.var_names.str.match(r"^Rpl|^Rps|^RPL|^RPS")
        sc.pp.calculate_qc_metrics(adata, qc_vars=["ribo"], inplace=True, percent_top=None)
        adata.obs.rename(columns={"pct_counts_ribo": "percent_ribo"}, inplace=True)

    return adata


adata = s6_cell_cycle_scoring(adata, mode=opt.mode, sample_name=opt.sample)

# ── Plots ────────────────────────────────────────────────────────────────────
fig, axes = plt.subplots(2, 2, figsize=(12, 8))
for ax, col in zip(axes.flat, ["S_score", "G2M_score", "G1_score", "CC_difference"]):
    data_by_phase = [adata.obs.loc[adata.obs["phase"] == ph, col] for ph in adata.obs["phase"].unique()]
    ax.violinplot(data_by_phase, showmedians=True)
    ax.set_xticks(range(1, len(adata.obs["phase"].unique()) + 1))
    ax.set_xticklabels(adata.obs["phase"].unique())
    ax.set_title(col)
fig.suptitle(f"{opt.sample} — Cell cycle scores by phase")
fig.tight_layout(); fig.savefig("cc_scores_by_phase.png", dpi=150); plt.close(fig)

fig, ax = plt.subplots(figsize=(7, 6))
for phase in adata.obs["phase"].unique():
    sel = (adata.obs["phase"] == phase).to_numpy()
    ax.scatter(adata.obs.loc[sel, "S_score"], adata.obs.loc[sel, "G2M_score"], s=4, label=phase)
ax.set_xlabel("S.Score"); ax.set_ylabel("G2M.Score")
ax.set_title(f"{opt.sample} — S vs G2M score")
ax.legend()
fig.tight_layout(); fig.savefig("cc_s_vs_g2m_scatter.png", dpi=150); plt.close(fig)

# ── Summary ──────────────────────────────────────────────────────────────────
phase_tbl = adata.obs.groupby(["name", "phase"]).size().reset_index(name="n_cells")
phase_tbl.columns = ["sample", "phase", "n_cells"]

score_summary = adata.obs.groupby("name")[["S_score", "G2M_score", "G1_score", "CC_difference"]].median()
score_summary = score_summary.reset_index().rename(columns={"name": "sample"})

merged = phase_tbl.merge(score_summary, on="sample", how="left")
merged.to_csv("cell_cycle_s6_summary.csv", index=False)

adata.write_h5ad(f"{opt.sample}_s6.h5ad")
print("Step 6 done.")
PYEOF

    python3 run_cell_cycle_s6.py \\
        --h5ad   "${h5ad}" \\
        --sample "${sample}" \\
        --mode   "${mode}"
    """
}
