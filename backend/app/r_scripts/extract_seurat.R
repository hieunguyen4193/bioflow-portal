suppressPackageStartupMessages(library(Seurat))
suppressPackageStartupMessages(library(jsonlite))

args <- commandArgs(trailingOnly = TRUE)
rds_path <- args[1]

s.obj <- readRDS(rds_path)

# Join layers if Seurat v5
if (inherits(s.obj[["RNA"]], "Assay5")) {
  tryCatch(s.obj <- JoinLayers(s.obj), error = function(e) NULL)
}

# Reductions: take first 2 dims of each
reductions <- list()
for (red in names(s.obj@reductions)) {
  emb <- tryCatch(as.data.frame(s.obj@reductions[[red]]@cell.embeddings), error = function(e) NULL)
  if (!is.null(emb) && ncol(emb) >= 2) {
    reductions[[red]] <- list(
      x     = as.numeric(emb[, 1]),
      y     = as.numeric(emb[, 2]),
      cells = rownames(emb)
    )
  }
}

# Metadata — convert everything to character to keep JSON simple
meta <- s.obj@meta.data
meta_out <- lapply(meta, function(col) as.character(col))

# Gene list
genes <- rownames(s.obj)

# Assays
assays <- names(s.obj@assays)

result <- list(
  n_cells    = ncol(s.obj),
  n_features = nrow(s.obj),
  assays     = assays,
  reductions = reductions,
  metadata   = meta_out,
  cells      = rownames(meta),
  genes      = genes
)

cat(toJSON(result, auto_unbox = TRUE, null = "null"))
