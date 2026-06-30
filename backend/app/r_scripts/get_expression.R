suppressPackageStartupMessages(library(Seurat))
suppressPackageStartupMessages(library(jsonlite))

args        <- commandArgs(trailingOnly = TRUE)
rds_path    <- args[1]
genes_str   <- args[2]   # comma-separated
assay_name  <- args[3]
slot_name   <- args[4]   # data | counts | scale.data

s.obj <- readRDS(rds_path)
if (inherits(s.obj[["RNA"]], "Assay5")) {
  tryCatch(s.obj <- JoinLayers(s.obj), error = function(e) NULL)
}

DefaultAssay(s.obj) <- assay_name

genes <- trimws(strsplit(genes_str, ",")[[1]])
genes <- genes[genes %in% rownames(s.obj)]

fetch_gene <- function(g) {
  # Try Seurat v5 (layer=) then Seurat v4 (slot=) then GetAssayData fallback
  val <- tryCatch(
    as.numeric(FetchData(s.obj, vars = g, layer = slot_name)[, 1]),
    error = function(e) NULL
  )
  if (!is.null(val)) return(val)

  val <- tryCatch(
    as.numeric(FetchData(s.obj, vars = g, slot = slot_name)[, 1]),
    error = function(e) NULL
  )
  if (!is.null(val)) return(val)

  # Last resort: pull directly from assay matrix
  tryCatch({
    mat <- GetAssayData(s.obj, assay = assay_name, layer = slot_name)
    as.numeric(mat[g, ])
  }, error = function(e)
    tryCatch({
      mat <- GetAssayData(s.obj, assay = assay_name, slot = slot_name)
      as.numeric(mat[g, ])
    }, error = function(e2) rep(0, ncol(s.obj)))
  )
}

expr_list <- list()
for (g in genes) {
  expr_list[[g]] <- fetch_gene(g)
}

result <- list(
  cells      = colnames(s.obj),
  expression = expr_list
)
cat(toJSON(result, auto_unbox = TRUE))
