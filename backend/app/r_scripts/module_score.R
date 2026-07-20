suppressPackageStartupMessages({
  library(Seurat)
  library(dplyr)
  library(tidyr)
  library(tibble)
  library(matrixStats)
  library(ggplot2)
  library(jsonlite)
  library(tools)
})

# ── calculate_module_score ──────────────────────────────────────────────────
# gene.list: data.frame with one column per module, gene symbols as values
#            (as produced by reading the module-list csv/xls/xlsx upload).
# Adds one "module_<name>_1" metadata column per module via Seurat::AddModuleScore.
# Modules with zero genes present in the object are skipped rather than erroring.
calculate_module_score <- function(s.obj, gene.list, assay = "SCT", ctrl = 50) {
  DefaultAssay(s.obj) <- assay

  for (module_name in colnames(gene.list)) {
    genes <- unique(gene.list[[module_name]])
    genes <- genes[!is.na(genes) & genes != ""]
    clean_name <- gsub(" ", "_", module_name)

    present <- intersect(genes, rownames(s.obj))
    missing <- setdiff(genes, rownames(s.obj))
    if (length(missing) > 0) {
      message(sprintf("[%s] %d/%d genes not found in the object: %s",
                       clean_name, length(missing), length(genes), paste(missing, collapse = ", ")))
    }
    if (length(present) == 0) {
      message(sprintf("[%s] skipped — none of its genes are present in the object", clean_name))
      next
    }

    s.obj <- AddModuleScore(
      object   = s.obj,
      features = list(present),
      name     = sprintf("module_%s_", clean_name),
      ctrl     = ctrl
    )
  }
  s.obj
}

# ── plot_module_score_heatmap ───────────────────────────────────────────────
# Mean module score per cluster, row (module) z-scored, plotted as a tile heatmap.
# s.obj must already carry "module_*" metadata columns from calculate_module_score().
plot_module_score_heatmap <- function(s.obj, cluster_col) {
  meta <- s.obj@meta.data
  module_cols <- grep("^module_", colnames(meta), value = TRUE)
  if (length(module_cols) == 0) {
    stop("No module score columns found in the object — run calculate_module_score() first.")
  }
  if (!cluster_col %in% colnames(meta)) {
    stop(sprintf("Cluster column '%s' not found in the object's metadata.", cluster_col))
  }

  heatmapdf <- meta[, c(cluster_col, module_cols)] %>%
    group_by(.data[[cluster_col]]) %>%
    summarise(across(everything(), mean), .groups = "drop") %>%
    column_to_rownames(cluster_col) %>%
    t() %>%
    as.data.frame()

  # AddModuleScore names columns "module_<name>_1" (single feature list -> index 1)
  rownames(heatmapdf) <- gsub("_1$", "", rownames(heatmapdf))

  row_sd <- matrixStats::rowSds(as.matrix(heatmapdf))
  heatmapdf.scaled <- (heatmapdf - rowMeans(heatmapdf)) / row_sd

  heatmapdf.scaled %>%
    rownames_to_column("signature") %>%
    pivot_longer(-signature, names_to = "cluster", values_to = "z_score") %>%
    ggplot(aes(x = cluster, y = signature, fill = z_score)) +
    geom_tile() +
    scale_fill_distiller(palette = "RdBu") +
    theme(axis.text.x = element_text(size = 22, angle = 90),
          axis.text.y = element_text(size = 22))
}

# ── CLI entry point ──────────────────────────────────────────────────────────
# Usage: Rscript module_score.R <rds_path> <gene_list_path> [assay] [ctrl]
# Prints {cells, expression} JSON — same shape as get_expression.R — so the app's
# per-cell UMAP/violin plotting code can treat each module like a synthetic gene;
# the heatmap (mean per cluster, row z-scored) is likewise computed client-side
# from this same per-cell data, reusing whichever metadata column is selected as
# "colour by" rather than a fixed cluster column baked in on the R side.
args <- commandArgs(trailingOnly = TRUE)
if (length(args) > 0) {
  rds_path       <- args[1]
  gene_list_path <- args[2]
  assay_name     <- if (length(args) >= 3 && nchar(args[3]) > 0) args[3] else "SCT"
  ctrl           <- if (length(args) >= 4 && nchar(args[4]) > 0) as.numeric(args[4]) else 50

  s.obj <- readRDS(rds_path)
  if (inherits(s.obj[["RNA"]], "Assay5")) {
    tryCatch(s.obj <- JoinLayers(s.obj), error = function(e) NULL)
  }

  ext <- file_ext(gene_list_path)
  gene.list <- switch(ext,
    csv  = read.csv(gene_list_path, stringsAsFactors = FALSE),
    xls  = readxl::read_excel(gene_list_path),
    xlsx = readxl::read_excel(gene_list_path),
    stop(sprintf("Unsupported gene list file type: .%s (expected .csv, .xls, or .xlsx)", ext))
  )

  s.obj <- calculate_module_score(s.obj, gene.list, assay = assay_name, ctrl = ctrl)

  module_cols <- grep("^module_", colnames(s.obj@meta.data), value = TRUE)
  expr_list <- setNames(
    lapply(module_cols, function(col) as.numeric(s.obj@meta.data[[col]])),
    gsub("_1$", "", module_cols)
  )
  result <- list(cells = colnames(s.obj), expression = expr_list)
  cat(toJSON(result, auto_unbox = TRUE, na = "null"))
}
