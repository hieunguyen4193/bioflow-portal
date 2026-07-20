// Step 7 — V/J gene usage (heavy chain = VDJ_1, light chain = VJ_1) and
// CDR3 length spectratype.
process GENE_USAGE_SPECTRATYPE {
    publishDir "${params.outdir}/s7_gene_usage_spectratype", mode: 'copy'

    input:
    path adata_h5ad

    output:
    path "v_gene_usage_heavy.tsv", emit: v_usage_heavy
    path "v_gene_usage_light.tsv", emit: v_usage_light
    path "spectratype.tsv",        emit: spectratype
    path "spectratype.png",        emit: plot

    script:
    """
    cat > run_gene_usage.py << 'PYEOF'
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

def gene_usage(chain, field, out_tsv):
    try:
        s = ir.get.airr(adata, field, chain=chain)
        counts = s.value_counts(dropna=True).reset_index()
        counts.columns = [field, "n_cells"]
        counts.to_csv(out_tsv, sep="\\t", index=False)
    except Exception as e:
        print(f"Skipping gene usage for {chain}/{field}: {e}")
        with open(out_tsv, "w") as f:
            f.write(f"# unavailable: {e}\\n")

gene_usage("VDJ_1", "v_call", "v_gene_usage_heavy.tsv")
gene_usage("VJ_1",  "v_call", "v_gene_usage_light.tsv")

try:
    ir.tl.spectratype(adata, chain="VDJ_1", cdr3_col="junction_aa", groupby="sample_id")
except Exception as e:
    print(f"spectratype tool call skipped: {e}")

try:
    ax = ir.pl.spectratype(adata, chain="VDJ_1", cdr3_col="junction_aa", groupby="sample_id")
    ax.figure.savefig("spectratype.png", dpi=150, bbox_inches="tight")
except Exception as e:
    print(f"Falling back to placeholder spectratype plot: {e}")
    placeholder_png("spectratype.png", f"spectratype plot unavailable:\\n{e}")

try:
    lengths = ir.get.airr(adata, "junction_aa", chain="VDJ_1").dropna().str.len()
    lengths.value_counts().sort_index().rename_axis("cdr3_aa_length").reset_index(name="n_cells").to_csv(
        "spectratype.tsv", sep="\\t", index=False
    )
except Exception as e:
    print(f"Skipping spectratype table: {e}")
    with open("spectratype.tsv", "w") as f:
        f.write(f"# unavailable: {e}\\n")
PYEOF

    python3 run_gene_usage.py
    """
}
