suppressPackageStartupMessages(library(Seurat))
suppressPackageStartupMessages(library(jsonlite))

args       <- commandArgs(trailingOnly = TRUE)
rds_path   <- args[1]
cache_path <- args[2]

s.obj <- readRDS(rds_path)
if (inherits(s.obj[["RNA"]], "Assay5")) {
  tryCatch(s.obj <- JoinLayers(s.obj), error = function(e) NULL)
}

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

cache <- list(cells = colnames(s.obj))
for (assay_name in names(s.obj@assays)) {
  mat <- get_mat(assay_name)
  if (!is.null(mat) && nrow(mat) > 0) {
    cache[[assay_name]] <- mat  # stays as sparse dgCMatrix
  }
}

saveRDS(cache, cache_path, compress = FALSE)  # compress=FALSE for faster reads
cat(toJSON(list(status = "ok", assays = names(s.obj@assays)), auto_unbox = TRUE))
