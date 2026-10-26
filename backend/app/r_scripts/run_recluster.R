suppressPackageStartupMessages({
  library(Seurat)
  library(jsonlite)
})

args               <- commandArgs(trailingOnly = TRUE)
rds_path           <- args[1]
cluster_resolution <- as.numeric(args[2])
algorithm          <- as.integer(args[3])
reduction          <- args[4]   # "" = reuse the stored SNN graph
num_pcs            <- as.integer(args[5])
column_name        <- args[6]
save_to_original   <- tolower(args[7]) == "true"
tmp_rds_path       <- args[8]

# Deliberately no JoinLayers here (unlike the other scripts): FindClusters only
# needs the SNN graph, and when save_to_original is set this object is written
# back over the preset — joining would silently change its layer layout.
s.obj <- readRDS(rds_path)

if (save_to_original && column_name %in% colnames(s.obj@meta.data))
  stop(sprintf("Metadata column '%s' already exists in the original object — pick a different column name.", column_name))

# ── Pick the SNN graph to cluster on. By default reuse the stored one, so only the
# resolution changes. Note the basic Seurat pipeline runs FindNeighbors once per
# integration method into the same "<assay>_snn" name, so on integrated objects
# the stored graph is the last one built (harmony) — pick a reduction explicitly
# to cluster on CCA/RPCA instead. A rebuilt graph uses the pipeline's own
# FindNeighbors call (dims 1:num_pcs, Seurat defaults otherwise).
build_graph_from <- function(red) {
  if (!(red %in% names(s.obj@reductions)))
    stop(sprintf("Reduction '%s' not found. Available: %s", red, paste(names(s.obj@reductions), collapse = ", ")))
  dims <- 1:min(num_pcs, ncol(s.obj@reductions[[red]]@cell.embeddings))
  # Own graph names so the stored "<assay>_snn" graph is never overwritten.
  safe <- gsub("[^A-Za-z0-9]", "_", red)
  message(sprintf("Running FindNeighbors on '%s' (dims 1:%d)", red, max(dims)))
  s.obj <<- FindNeighbors(s.obj, dims = dims, reduction = red,
                          graph.name = paste0("recluster_", safe, c("_nn", "_snn")), verbose = TRUE)
  paste0("recluster_", safe, "_snn")
}

graph_names <- names(s.obj@graphs)
snn_graphs  <- graph_names[grepl("_snn$", graph_names)]
preferred   <- paste0(DefaultAssay(s.obj), "_snn")
built_graph <- FALSE

if (nchar(reduction) > 0) {
  graph_name  <- build_graph_from(reduction)
  built_graph <- TRUE
} else if (length(snn_graphs) > 0) {
  graph_name <- if (preferred %in% snn_graphs) preferred else snn_graphs[1]
  message(sprintf("Reusing existing graph '%s'", graph_name))
} else {
  # The pipeline names its PCA "RNA_PCA"; plain Seurat objects use "pca".
  reds <- names(s.obj@reductions)
  pca_red <- c(intersect(c("pca", "RNA_PCA"), reds), grep("pca", reds, ignore.case = TRUE, value = TRUE))[1]
  if (is.na(pca_red))
    stop("This object has neither an SNN graph nor a PCA reduction to build one from.")
  message("No SNN graph found in the object")
  reduction   <- pca_red
  graph_name  <- build_graph_from(pca_red)
  built_graph <- TRUE
}

# FindClusters overwrites seurat_clusters/Idents and adds a "<graph>_res.<res>"
# column — snapshot and restore them so the only change is the new column.
orig_meta   <- s.obj@meta.data
orig_idents <- Idents(s.obj)

s.obj <- FindClusters(s.obj, graph.name = graph_name, resolution = cluster_resolution,
                      algorithm = algorithm, random.seed = 0, verbose = TRUE)  # Seurat's default seed, as the pipeline uses
new_clusters <- as.character(s.obj$seurat_clusters)

s.obj@meta.data <- orig_meta
Idents(s.obj)   <- orig_idents
# Don't persist graphs built just for this run into the preset — only the new column.
if (built_graph) s.obj@graphs[paste0("recluster_", gsub("[^A-Za-z0-9]", "_", reduction), c("_nn", "_snn"))] <- NULL
s.obj <- AddMetaData(
  s.obj,
  metadata = setNames(factor(new_clusters, levels = as.character(sort(unique(as.integer(new_clusters))))),
                      colnames(s.obj)),
  col.name = column_name
)

if (save_to_original) {
  # Write next to the original, then rename over it — rename is atomic on the same
  # filesystem, so a reader (or a cancelled run) never sees a half-written preset.
  saveRDS(s.obj, tmp_rds_path)
  Sys.chmod(tmp_rds_path, file.info(rds_path)$mode)
  if (!file.rename(tmp_rds_path, rds_path))
    stop(sprintf("Failed to replace %s with the updated object", rds_path))
  message(sprintf("Saved column '%s' into %s", column_name, rds_path))
}

sizes <- table(new_clusters)
sizes <- sizes[order(as.integer(names(sizes)))]

result <- list(
  column        = column_name,
  graph         = graph_name,
  built_graph   = built_graph,
  reduction     = if (built_graph) reduction else NA,
  resolution    = cluster_resolution,
  n_clusters    = length(sizes),
  cluster_sizes = as.list(setNames(as.integer(sizes), names(sizes))),
  values        = new_clusters,
  cells         = colnames(s.obj),
  saved         = save_to_original
)
cat(toJSON(result, auto_unbox = TRUE, na = "null"))
