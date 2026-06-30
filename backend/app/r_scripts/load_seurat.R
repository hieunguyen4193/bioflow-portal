suppressPackageStartupMessages(library(Seurat))
suppressPackageStartupMessages(library(jsonlite))

args       <- commandArgs(trailingOnly = TRUE)
rds_path   <- args[1]
cache_base <- args[2]   # file prefix for binary matrices

s.obj <- readRDS(rds_path)
if (inherits(s.obj[["RNA"]], "Assay5")) {
  tryCatch(s.obj <- JoinLayers(s.obj), error = function(e) NULL)
}

# ── 1. Metadata (same as extract_seurat.R) ────────────────────────────────
reductions <- list()
for (red_name in names(s.obj@reductions)) {
  emb <- tryCatch(
    as.data.frame(s.obj@reductions[[red_name]]@cell.embeddings),
    error = function(e) NULL
  )
  if (!is.null(emb) && ncol(emb) >= 2) {
    reductions[[red_name]] <- list(
      x     = as.numeric(emb[, 1]),
      y     = as.numeric(emb[, 2]),
      cells = rownames(emb)
    )
  }
}

meta_out <- lapply(s.obj@meta.data, function(col) as.character(col))
assays   <- names(s.obj@assays)

result <- list(
  n_cells    = ncol(s.obj),
  n_features = nrow(s.obj),
  assays     = assays,
  reductions = reductions,
  metadata   = meta_out,
  cells      = rownames(s.obj@meta.data),
  genes      = rownames(s.obj)
)
# Print metadata JSON first — backend reads this from stdout
cat(toJSON(result, auto_unbox = TRUE, null = "null"))
cat("\n")
flush(stdout())

# ── 2. Save expression matrices as float32 binary (one file per assay) ───
get_mat <- function(assay_name) {
  tryCatch(
    GetAssayData(s.obj, assay = assay_name, layer = "data"),
    error = function(e)
      tryCatch(
        GetAssayData(s.obj, assay = assay_name, slot = "data"),
        error = function(e2) NULL
      )
  )
}

for (assay_name in assays) {
  mat <- get_mat(assay_name)
  if (is.null(mat) || nrow(mat) == 0) next

  genes   <- rownames(mat)
  cells   <- colnames(mat)
  n_genes <- length(genes)
  n_cells <- length(cells)

  meta_path <- paste0(cache_base, "_", assay_name, ".json")
  bin_path  <- paste0(cache_base, "_", assay_name, ".bin")

  writeLines(
    toJSON(list(genes = genes, cells = cells, n_genes = n_genes, n_cells = n_cells),
           auto_unbox = TRUE),
    meta_path
  )

  # Row-major float32: each gene occupies a contiguous block of n_cells values
  con <- file(bin_path, "wb")
  for (i in seq_len(n_genes)) {
    writeBin(as.numeric(mat[i, ]), con, size = 4L)
  }
  close(con)

  message("Cached assay: ", assay_name, " (", n_genes, " genes x ", n_cells, " cells)")
}
