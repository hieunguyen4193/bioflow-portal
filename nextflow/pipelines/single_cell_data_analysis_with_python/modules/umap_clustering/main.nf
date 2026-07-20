process UMAP_CLUSTERING {
    tag "${sample}"
    publishDir "${params.outdir}/s8_umap_clustering",               mode: "copy"

    input:
    tuple val(sample), path(h5ad)
    val  use_sctransform
    val  num_PCA
    val  num_PC_used_in_UMAP
    val  num_PC_used_in_Clustering
    val  cluster_resolution
    val  vars_to_regress
    val  remove_genes

    output:
    tuple val(sample), path("${sample}_s8.h5ad"), emit: anndata

    script:
    """
    cat > run_s8.py << 'PYEOF'
import argparse

import numpy as np
import scanpy as sc

sc.settings.verbosity = 1

p = argparse.ArgumentParser()
p.add_argument("--h5ad",                       type=str)
p.add_argument("--sample",                     type=str, default="sample")
p.add_argument("--use_sctransform",            type=str, default="false")
p.add_argument("--num_PCA",                    type=int, default=50)
p.add_argument("--num_PC_used_in_UMAP",        type=int, default=30)
p.add_argument("--num_PC_used_in_Clustering",  type=int, default=30)
p.add_argument("--cluster_resolution",         type=float, default=0.5)
p.add_argument("--vars_to_regress",            type=str, default="percent.mt")
p.add_argument("--remove_genes",               type=str, default="none")
opt = p.parse_args()

use_sctransform = opt.use_sctransform.lower() == "true"
vars_to_regress = None if opt.vars_to_regress == "none" else \\
    [v.strip().replace(".", "_") for v in opt.vars_to_regress.split(",")]
remove_genes = None if opt.remove_genes == "none" else \\
    [g.strip() for g in opt.remove_genes.split(",")]

adata = sc.read_h5ad(opt.h5ad)


def store_neighbors_under_key(adata, source_uns_neighbors, source_obsp, key):
    \"\"\"Copy a computed neighbors graph into a namespaced slot so multiple
    graphs (one per reduction/integration) can coexist on the same AnnData,
    mirroring how the R pipeline keeps separate reductions per method.\"\"\"
    conn_key = f"{key}_connectivities"
    dist_key = f"{key}_distances"
    adata.obsp[conn_key] = source_obsp["connectivities"]
    adata.obsp[dist_key] = source_obsp["distances"]
    adata.uns[key] = dict(source_uns_neighbors)
    adata.uns[key]["connectivities_key"] = conn_key
    adata.uns[key]["distances_key"] = dist_key


def s8_integration_and_clustering(adata, use_sctransform, num_pca, num_pc_umap,
                                   num_pc_clustering, cluster_resolution,
                                   vars_to_regress, remove_genes):

    if use_sctransform:
        sc.experimental.pp.normalize_pearson_residuals(adata)
        sc.pp.highly_variable_genes(adata, flavor="seurat_v3", n_top_genes=2000)
    else:
        sc.pp.normalize_total(adata, target_sum=1e4)
        sc.pp.log1p(adata)
        sc.pp.highly_variable_genes(adata, flavor="seurat")
        sc.pp.scale(adata)
        if vars_to_regress:
            sc.pp.regress_out(adata, keys=vars_to_regress)

    hvg_mask = adata.var["highly_variable"].copy()
    if remove_genes:
        hvg_mask &= ~adata.var_names.isin(remove_genes)

    sc.tl.pca(adata, n_comps=min(num_pca, adata.n_obs - 1), mask_var=hvg_mask.to_numpy())
    adata.obsm["RNA_PCA"] = adata.obsm["X_pca"]

    # ── Unintegrated UMAP ────────────────────────────────────────────────────
    sc.pp.neighbors(adata, n_pcs=min(num_pc_umap, adata.obsm["RNA_PCA"].shape[1]),
                     use_rep="RNA_PCA", key_added="RNA_PCA_neighbors")
    sc.tl.umap(adata, neighbors_key="RNA_PCA_neighbors")
    adata.obsm["RNA_UMAP"] = adata.obsm["X_umap"]
    print("UMAP (unintegrated) finished.")

    n_samples = adata.obs["name"].nunique()
    do_integration = n_samples >= 2
    reductions = ["RNA_PCA"]

    if do_integration:
        # ── Harmony — exact algorithmic equivalent of Seurat's HarmonyIntegration ──
        try:
            sc.external.pp.harmony_integrate(adata, key="name", basis="RNA_PCA",
                                              adjusted_basis="harmony")
            reductions.append("harmony")
            print("Integrating with Harmony ... done.")
        except Exception as exc:
            print(f"Harmony integration failed ({exc}) — skipping.")

        # ── "CCA"-equivalent — Scanorama (closest widely-used Python analogue;
        # not a literal port of Seurat's CCA integration) ──────────────────────
        try:
            import scanorama
            batches = list(adata.obs["name"].unique())
            adatas_by_batch = [adata[adata.obs["name"] == b].copy() for b in batches]
            integrated, _ = scanorama.integrate_scanpy(adatas_by_batch, dimred=num_pca)
            cca_embedding = np.zeros((adata.n_obs, num_pca))
            for b, emb, sub in zip(batches, integrated, adatas_by_batch):
                idx = adata.obs_names.get_indexer(sub.obs_names)
                cca_embedding[idx, :] = emb
            adata.obsm["integrated_cca"] = cca_embedding
            reductions.append("integrated_cca")
            print("Integrating with Scanorama (CCA-equivalent) ... done.")
        except Exception as exc:
            print(f"Scanorama integration failed ({exc}) — skipping.")

        # ── "RPCA"-equivalent — BBKNN (closest widely-used Python analogue;
        # not a literal port of Seurat's RPCA integration) ────────────────────
        try:
            import bbknn
            adata_bbknn = adata.copy()
            bbknn.bbknn(adata_bbknn, batch_key="name",
                        n_pcs=min(num_pc_clustering, adata.obsm["RNA_PCA"].shape[1]))
            store_neighbors_under_key(adata, adata_bbknn.uns["neighbors"],
                                       adata_bbknn.obsp, "integrated_rpca_neighbors")
            reductions.append("integrated_rpca")
            print("Integrating with BBKNN (RPCA-equivalent) ... done.")
        except Exception as exc:
            print(f"BBKNN integration failed ({exc}) — skipping.")
    else:
        print("Single sample — skipping CCA/RPCA/Harmony integration.")

    for reduction in reductions:
        new_reduction_name = "".join(c if c.isalnum() else "_" for c in reduction)
        cluster_key = f"{new_reduction_name}.cluster.{cluster_resolution}"
        umap_key = f"{new_reduction_name}_UMAP"

        if reduction == "integrated_rpca":
            # BBKNN already produced the graph directly (no embedding to re-run
            # neighbors on) — reuse the namespaced graph built above.
            neighbors_key = "integrated_rpca_neighbors"
        else:
            neighbors_key = f"{new_reduction_name}_neighbors"
            if neighbors_key not in adata.uns:
                sc.pp.neighbors(adata, n_pcs=min(num_pc_clustering, adata.obsm[reduction].shape[1]),
                                 use_rep=reduction, key_added=neighbors_key)

        sc.tl.leiden(adata, neighbors_key=neighbors_key, resolution=cluster_resolution,
                      key_added=cluster_key)
        sc.tl.umap(adata, neighbors_key=neighbors_key)
        adata.obsm[umap_key] = adata.obsm["X_umap"]
        print(f"Done: {reduction}")

    return adata


adata = s8_integration_and_clustering(
    adata,
    use_sctransform=use_sctransform,
    num_pca=opt.num_PCA,
    num_pc_umap=opt.num_PC_used_in_UMAP,
    num_pc_clustering=opt.num_PC_used_in_Clustering,
    cluster_resolution=opt.cluster_resolution,
    vars_to_regress=vars_to_regress,
    remove_genes=remove_genes,
)

adata.write_h5ad(f"{opt.sample}_s8.h5ad")
print("Step 8 complete.")
PYEOF

    python3 run_s8.py \\
        --h5ad                      "${h5ad}" \\
        --sample                    "${sample}" \\
        --use_sctransform           "${use_sctransform}" \\
        --num_PCA                   ${num_PCA} \\
        --num_PC_used_in_UMAP       ${num_PC_used_in_UMAP} \\
        --num_PC_used_in_Clustering ${num_PC_used_in_Clustering} \\
        --cluster_resolution        ${cluster_resolution} \\
        --vars_to_regress           "${vars_to_regress}" \\
        --remove_genes              "${remove_genes}"
    """
}
