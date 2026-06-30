suppressPackageStartupMessages(library(Seurat))
suppressPackageStartupMessages(library(jsonlite))

args       <- commandArgs(trailingOnly = TRUE)
rds_path   <- args[1]
cache_base <- args[2]
assay_name <- args[3]
slot_name  <- args[4]   # "data", "counts", or "scale.data"

s.obj <- readRDS(rds_path)
if (!is.null(s.obj[["RNA"]]) && inherits(s.obj[["RNA"]], "Assay5")) {
  tryCatch(s.obj <- JoinLayers(s.obj), error = function(e) NULL)
}

if (!(assay_name %in% names(s.obj@assays))) {
  stop(paste0("Assay '", assay_name, "' not found. Available: ",
              paste(names(s.obj@assays), collapse = ", ")))
}

DefaultAssay(s.obj) <- assay_name

mat <- tryCatch(
  GetAssayData(s.obj, assay = assay_name, layer = slot_name),
  error = function(e)
    tryCatch(
      GetAssayData(s.obj, assay = assay_name, slot = slot_name),
      error = function(e2) NULL
    )
)

if (is.null(mat) || nrow(mat) == 0) {
  assay_obj <- s.obj[[assay_name]]
  avail <- tryCatch(
    paste(names(assay_obj@layers), collapse = ", "),
    error = function(e) tryCatch(
      paste(slotNames(assay_obj), collapse = ", "),
      error = function(e2) "unknown"
    )
  )
  stop(paste0("Slot '", slot_name, "' not found in assay '", assay_name,
              "'. Available: ", avail))
}

genes   <- rownames(mat)
cells   <- colnames(mat)
n_genes <- length(genes)
n_cells <- length(cells)

meta_path <- paste0(cache_base, "_", assay_name, "_", slot_name, ".json")
bin_path  <- paste0(cache_base, "_", assay_name, "_", slot_name, ".bin")

writeLines(
  toJSON(list(
    genes   = genes,  cells   = cells,
    n_genes = n_genes, n_cells = n_cells,
    assay   = assay_name, slot = slot_name
  ), auto_unbox = TRUE),
  meta_path
)

con <- file(bin_path, "wb")
for (i in seq_len(n_genes)) {
  writeBin(as.numeric(mat[i, ]), con, size = 4L)
}
close(con)

message("Cached assay=", assay_name, " slot=", slot_name,
        " (", n_genes, " genes x ", n_cells, " cells)")
