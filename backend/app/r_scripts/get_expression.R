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

genes <- trimws(strsplit(genes_str, ",")[[1]])
genes <- genes[genes %in% rownames(s.obj)]

DefaultAssay(s.obj) <- assay_name

expr_list <- list()
for (g in genes) {
  vals <- tryCatch(
    as.numeric(FetchData(s.obj, vars = g, slot = slot_name)[, 1]),
    error = function(e) rep(0, ncol(s.obj))
  )
  expr_list[[g]] <- vals
}

result <- list(
  cells      = colnames(s.obj),
  expression = expr_list
)
cat(toJSON(result, auto_unbox = TRUE))
