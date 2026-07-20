// Step 1 — Load each sample's 10x Genomics cellranger vdj contig annotations
// via scirpy and concatenate into a single AnnData object.
process LOAD_10X_VDJ {
    publishDir "${params.outdir}/s1_load", mode: 'copy'

    input:
    path samplesheet

    output:
    path "combined.h5ad",       emit: adata
    path "sample_summary.tsv",  emit: summary

    script:
    """
    cat > run_load.py << 'PYEOF'
import pandas as pd
import anndata as ad
import scirpy as ir

df = pd.read_csv("${samplesheet}")

adatas = []
for _, row in df.iterrows():
    sample_id = str(row["SampleID"])
    subject = row["subject"] if "subject" in df.columns and pd.notna(row.get("subject")) else ""
    subject = str(subject).strip() or sample_id

    a = ir.io.read_10x_vdj(row["contig_annotations"])
    a.obs["sample_id"] = sample_id
    a.obs["subject"] = subject
    a.obs_names = [f"{sample_id}_{bc}" for bc in a.obs_names]
    adatas.append(a)

adata = ad.concat(adatas, join="outer")
adata.write_h5ad("combined.h5ad")

summary = adata.obs.groupby("sample_id").size().reset_index(name="n_cells")
summary.to_csv("sample_summary.tsv", sep="\\t", index=False)
PYEOF

    python3 run_load.py
    """
}
