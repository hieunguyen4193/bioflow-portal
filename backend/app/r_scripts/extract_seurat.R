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

# Assays and their available slots/layers
assays <- names(s.obj@assays)

get_assay_slots <- function(assay_name) {
  assay_obj <- s.obj[[assay_name]]
  # Seurat v5: layers are named (e.g. "counts", "data")
  layers <- tryCatch(names(assay_obj@layers), error = function(e) NULL)
  if (!is.null(layers) && length(layers) > 0)
    return(sort(unique(as.character(layers))))
  # Seurat v4: check standard slots for non-empty matrices
  Filter(function(s) {
    tryCatch(nrow(GetAssayData(s.obj, assay = assay_name, slot = s)) > 0,
             error = function(e) FALSE)
  }, c("counts", "data", "scale.data"))
}

assay_slots <- setNames(lapply(assays, get_assay_slots), assays)

result <- list(
  n_cells     = ncol(s.obj),
  n_features  = nrow(s.obj),
  assays      = assays,
  assay_slots = assay_slots,
  reductions  = reductions,
  metadata    = meta_out,
  cells       = rownames(meta),
  genes       = genes
)

cat(toJSON(result, auto_unbox = TRUE, null = "null"))
