suppressPackageStartupMessages({
  library(Seurat)
  library(jsonlite)
})

args                <- commandArgs(trailingOnly = TRUE)
rds_path            <- args[1]
group_by            <- args[2]
clusters_arg        <- args[3]
use_sctransform     <- tolower(args[4]) == "true"
vars_to_regress_arg <- args[5]
num_pca             <- as.integer(args[6])
num_pcs_umap        <- as.integer(args[7])
num_pcs_cluster     <- as.integer(args[8])
cluster_resolution  <- as.numeric(args[9])
rm_tcr              <- tolower(args[10]) == "true"
rm_bcr              <- tolower(args[11]) == "true"
out_rds_path        <- args[12]

clusters        <- trimws(strsplit(clusters_arg, ",")[[1]])
vars.to.regress <- if (nchar(vars_to_regress_arg) > 0) trimws(strsplit(vars_to_regress_arg, ",")[[1]]) else character(0)

s.obj <- readRDS(rds_path)
if (inherits(s.obj[["RNA"]], "Assay5")) {
  tryCatch(s.obj <- JoinLayers(s.obj), error = function(e) NULL)
}

if (!(group_by %in% colnames(s.obj@meta.data)))
  stop(sprintf("Metadata column '%s' not found in this Seurat object.", group_by))

n_cells_before <- ncol(s.obj)
keep   <- as.character(s.obj@meta.data[[group_by]]) %in% clusters
n_keep <- sum(keep)
# FindNeighbors/UMAP need enough cells to build a sensible k-NN graph — below this,
# the run either errors deep inside Seurat or produces a degenerate one-point UMAP,
# so fail fast with a message that names the actual selection instead.
if (n_keep < 20)
  stop(sprintf("Only %d cells match the selected clusters (%s) in '%s' — need at least 20 to re-cluster.",
               n_keep, paste(clusters, collapse = ", "), group_by))

s.obj <- subset(s.obj, cells = colnames(s.obj)[keep])
message(sprintf("Subset: %d -> %d cells", n_cells_before, ncol(s.obj)))

# Drop prior reductions/graphs/scale.data from the parent object — they describe the
# full dataset, not this subset, and would otherwise linger as stale/misleading state
# (e.g. a "pca" reduction computed on 30k cells sitting on a 500-cell subset object).
DefaultAssay(s.obj) <- "RNA"
s.obj <- DietSeurat(s.obj, assays = "RNA")

# ── Species detection + TCR/BCR gene exclusion (same convention as run_dge.R) ─────
all.genes    <- rownames(s.obj)
sample.genes <- head(all.genes[nchar(all.genes) >= 3], 200)
pct_upper    <- mean(sample.genes == toupper(sample.genes), na.rm = TRUE)
is_human     <- pct_upper > 0.5
message(sprintf("Species detected: %s (%.0f%% uppercase genes sampled)",
                if (is_human) "human" else "mouse", pct_upper * 100))

TR_genes_patterns <- c("Trav", "Traj", "Trac", "Trbv", "Trbd", "Trbj", "Trbc",
                        "Trgv", "Trgj", "Trgc", "Trdv", "Trdc", "Trdj")
BR_genes_patterns <- c("Ighv", "Ighd", "Ighj", "Ighc", "Igkv",
                        "Igkj", "Igkc", "Iglv", "Iglj", "Iglc")
if (is_human) {
  TR_genes_patterns <- toupper(TR_genes_patterns)
  BR_genes_patterns <- toupper(BR_genes_patterns)
}

TCRgenes.to.exclude <- all.genes[substr(all.genes, 1, 4) %in% TR_genes_patterns]
BCRgenes.to.exclude <- all.genes[substr(all.genes, 1, 4) %in% BR_genes_patterns]

remove.genes <- character(0)
if (rm_tcr) remove.genes <- c(remove.genes, TCRgenes.to.exclude)
if (rm_bcr) remove.genes <- c(remove.genes, BCRgenes.to.exclude)
message(sprintf("Excluded from PCA — TCR: %d, BCR/Ig: %d",
                length(TCRgenes.to.exclude) * rm_tcr, length(BCRgenes.to.exclude) * rm_bcr))

# ── Re-normalise and re-cluster the subset from scratch ───────────────────────────
if (use_sctransform) {
  s.obj <- SCTransform(s.obj, vars.to.regress = vars.to.regress, verbose = TRUE)
} else {
  s.obj <- NormalizeData(s.obj, verbose = FALSE)
  s.obj <- FindVariableFeatures(s.obj, selection.method = "vst", verbose = FALSE)
  s.obj <- ScaleData(s.obj, features = VariableFeatures(s.obj),
                      vars.to.regress = if (length(vars.to.regress) > 0) vars.to.regress else NULL,
                      verbose = FALSE)
}

pca_features <- setdiff(VariableFeatures(s.obj), remove.genes)
s.obj <- RunPCA(s.obj, npcs = num_pca, features = pca_features, reduction.name = "pca", verbose = TRUE)
s.obj <- RunUMAP(s.obj, dims = 1:num_pcs_umap, reduction = "pca", reduction.name = "umap", verbose = TRUE)
s.obj <- FindNeighbors(s.obj, dims = 1:num_pcs_cluster, reduction = "pca", verbose = TRUE)
s.obj <- FindClusters(s.obj, resolution = cluster_resolution, random.seed = 42, verbose = TRUE)

saveRDS(s.obj, out_rds_path)
message(sprintf("Saved sub-clustered object: %s", out_rds_path))

# ── Emit frontend-ready metadata — same reductions/metadata/cells shape as
# extract_seurat.R, so the Explore UI can render a UMAP preview the same way it
# renders the main object's UMAP tab, without a second round-trip through R. ─────
reductions <- list()
for (red in names(s.obj@reductions)) {
  emb <- tryCatch(as.data.frame(s.obj@reductions[[red]]@cell.embeddings), error = function(e) NULL)
  if (!is.null(emb) && ncol(emb) >= 2) {
    reductions[[red]] <- list(x = as.numeric(emb[, 1]), y = as.numeric(emb[, 2]), cells = rownames(emb))
  }
}
meta     <- s.obj@meta.data
meta_out <- lapply(meta, function(col) as.character(col))

result <- list(
  n_cells_before = n_cells_before,
  n_cells_after  = ncol(s.obj),
  species        = if (is_human) "human" else "mouse",
  excluded_tcr   = if (rm_tcr) as.list(TCRgenes.to.exclude) else list(),
  excluded_bcr   = if (rm_bcr) as.list(BCRgenes.to.exclude) else list(),
  reductions     = reductions,
  metadata       = meta_out,
  cells          = rownames(meta)
)
cat(toJSON(result, auto_unbox = TRUE, na = "null"))
