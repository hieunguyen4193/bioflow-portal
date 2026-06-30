suppressPackageStartupMessages(library(Seurat))
suppressPackageStartupMessages(library(jsonlite))

args        <- commandArgs(trailingOnly = TRUE)
rds_path    <- args[1]
genes_str   <- args[2]   # comma-separated
assay_name  <- args[3]
slot_name   <- args[4]   # data | counts | scale.data
cache_path  <- if (length(args) >= 5) args[5] else ""

genes <- trimws(strsplit(genes_str, ",")[[1]])

# ── Fast path: use pre-built expression cache ─────────────────────────────────
if (nchar(cache_path) > 0 && file.exists(cache_path)) {
  cache <- readRDS(cache_path)
  mat   <- cache[[assay_name]]
  if (!is.null(mat)) {
    genes_found <- genes[genes %in% rownames(mat)]
    expr_list   <- list()
    for (g in genes_found) {
      expr_list[[g]] <- as.numeric(mat[g, ])
    }
    result <- list(cells = cache$cells, expression = expr_list)
    cat(toJSON(result, auto_unbox = TRUE))
    quit(save = "no", status = 0)
  }
}

# ── Slow path: load full Seurat object ────────────────────────────────────────
s.obj <- readRDS(rds_path)
if (inherits(s.obj[["RNA"]], "Assay5")) {
  tryCatch(s.obj <- JoinLayers(s.obj), error = function(e) NULL)
}

DefaultAssay(s.obj) <- assay_name
genes <- genes[genes %in% rownames(s.obj)]

fetch_gene <- function(g) {
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

result <- list(cells = colnames(s.obj), expression = expr_list)
cat(toJSON(result, auto_unbox = TRUE))
