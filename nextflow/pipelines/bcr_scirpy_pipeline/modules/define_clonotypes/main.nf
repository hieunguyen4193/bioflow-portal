// Step 3 — Clonotype definition.
// clustering_mode = "clonotypes": exact nt-sequence identity clonotypes
//   (ir.tl.define_clonotypes); sequence/metric are forced to nt/identity
//   regardless of the params below, since exact clonotyping is identity-based
//   by definition.
// clustering_mode = "clonotype_clusters": similarity-based clonotype clusters
//   (ir.tl.define_clonotype_clusters) using the user-selected sequence/metric.
process DEFINE_CLONOTYPES {
    publishDir "${params.outdir}/s3_define_clonotypes", mode: 'copy'

    input:
    path adata_h5ad
    val clustering_mode
    val sequence
    val metric
    val receptor_arms
    val dual_ir

    output:
    path "clonotyped.h5ad",       emit: adata
    path "clonotype_summary.tsv", emit: summary

    script:
    """
    cat > run_define_clonotypes.py << 'PYEOF'
import scanpy as sc
import scirpy as ir

adata = sc.read_h5ad("${adata_h5ad}")

mode          = "${clustering_mode}"
sequence      = "${sequence}"
metric        = "${metric}"
receptor_arms = "${receptor_arms}"
dual_ir       = "${dual_ir}"

if mode == "clonotype_clusters":
    ir.pp.ir_dist(adata, metric=metric, sequence=sequence)
    ir.tl.define_clonotype_clusters(
        adata,
        sequence=sequence,
        metric=metric,
        receptor_arms=receptor_arms,
        dual_ir=dual_ir,
        key_added="clone_id",
    )
else:
    # Exact clonotypes are always nt-identity based.
    ir.pp.ir_dist(adata, metric="identity", sequence="nt")
    ir.tl.define_clonotypes(
        adata,
        receptor_arms=receptor_arms,
        dual_ir=dual_ir,
        key_added="clone_id",
    )

adata.write_h5ad("clonotyped.h5ad")

n_clonotypes = adata.obs["clone_id"].nunique()
n_cells      = adata.n_obs
with open("clonotype_summary.tsv", "w") as f:
    f.write("metric_name\\tvalue\\n")
    f.write(f"n_clonotypes\\t{n_clonotypes}\\n")
    f.write(f"n_cells\\t{n_cells}\\n")
PYEOF

    python3 run_define_clonotypes.py
    """
}
