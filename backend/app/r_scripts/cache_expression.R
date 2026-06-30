suppressPackageStartupMessages(library(Seurat))
suppressPackageStartupMessages(library(jsonlite))

args        <- commandArgs(trailingOnly = TRUE)
rds_path    <- args[1]
cache_base  <- args[2]   # path prefix; we write {cache_base}_{assay}.bin + .json

s.obj <- readRDS(rds_path)
if (inherits(s.obj[["RNA"]], "Assay5")) {
  tryCatch(s.obj <- JoinLayers(s.obj), error = function(e) NULL)
}

cells <- colnames(s.obj)
saved <- c()

for (assay_name in names(s.obj@assays)) {
  mat <- tryCatch(
    GetAssayData(s.obj, assay = assay_name, layer = "data"),
    error = function(e)
      tryCatch(
        GetAssayData(s.obj, assay = assay_name, slot = "data"),
        error = function(e2) NULL
      )
  )
  if (is.null(mat) || nrow(mat) == 0) next

  genes     <- rownames(mat)
  bin_path  <- paste0(cache_base, "_", assay_name, ".bin")
  meta_path <- paste0(cache_base, "_", assay_name, ".json")

  # Write metadata
  writeLines(toJSON(list(genes = genes, cells = cells,
                         n_genes = length(genes), n_cells = length(cells)),
                    auto_unbox = TRUE), meta_path)

  # Write float32 binary, row-major (one gene per row = contiguous for fast Python slice)
  con <- file(bin_path, "wb")
  for (i in seq_len(nrow(mat))) {
    writeBin(as.numeric(mat[i, ]), con, size = 4L)
  }
  close(con)
  saved <- c(saved, assay_name)
}

cat(toJSON(list(status = "ok", assays = saved), auto_unbox = TRUE))
