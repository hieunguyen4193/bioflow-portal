suppressPackageStartupMessages(library(Seurat))
suppressPackageStartupMessages(library(jsonlite))
suppressPackageStartupMessages(library(dplyr))

args         <- commandArgs(trailingOnly = TRUE)
rds_path     <- args[1]
mode         <- args[2]   # "clusters" | "conditions"
group_by     <- args[3]   # metadata column
assay_name   <- args[4]
slot_name    <- args[5]
test_use     <- args[6]
ident1       <- if (length(args) >= 7 && nchar(args[7]) > 0) trimws(strsplit(args[7], ",")[[1]]) else character(0)
ident2       <- if (length(args) >= 8 && nchar(args[8]) > 0) trimws(strsplit(args[8], ",")[[1]]) else character(0)
rm_tcr       <- if (length(args) >= 9) args[9] == "true" else TRUE
rm_bcr       <- if (length(args) >= 10) args[10] == "true" else TRUE
min_pct      <- if (length(args) >= 11 && nchar(args[11]) > 0) as.numeric(args[11]) else 0.01

s.obj <- readRDS(rds_path)
if (inherits(s.obj[["RNA"]], "Assay5")) {
  tryCatch(s.obj <- JoinLayers(s.obj), error = function(e) NULL)
}
DefaultAssay(s.obj) <- assay_name
Idents(s.obj)       <- group_by

# ── Detect species from gene name casing ──────────────────────────────────────
# Human genes are predominantly uppercase (CD3E, FOXP3); mouse are mixed (Cd3e, Foxp3)
all.genes   <- rownames(s.obj)
sample.genes <- head(all.genes[nchar(all.genes) >= 3], 200)
pct_upper   <- mean(sample.genes == toupper(sample.genes), na.rm = TRUE)
is_human    <- pct_upper > 0.5
message(sprintf("Species detected: %s (%.0f%% uppercase genes sampled)",
                if (is_human) "human" else "mouse", pct_upper * 100))

TR_genes_patterns <- c("Trav", "Traj", "Trac", "Trbv", "Trbd", "Trbj", "Trbc",
                        "Trgv", "Trgj", "Trgc", "Trdv", "Trdc", "Trdj")
BR_genes_patterns <- c("Ighv", "Ighd", "Ighj", "Ighc", "Igkv",
                        "Igkj", "Igkc", "Iglv", "Iglj", "Iglc")
if (is_human) {
  TR_genes_patterns <- toupper(TR_genes_patterns)
  BR_genes_patterns <- toupper(BR_genes_patterns)
}

TCRgenes.to.exclude <- unlist(lapply(all.genes, function(x) {
  if (substr(x, 1, 4) %in% TR_genes_patterns) x else NA
}))
TCRgenes.to.exclude <- TCRgenes.to.exclude[!is.na(TCRgenes.to.exclude)]

BCRgenes.to.exclude <- unlist(lapply(all.genes, function(x) {
  if (substr(x, 1, 4) %in% BR_genes_patterns) x else NA
}))
BCRgenes.to.exclude <- BCRgenes.to.exclude[!is.na(BCRgenes.to.exclude)]

excluded <- character(0)
if (rm_tcr) excluded <- c(excluded, TCRgenes.to.exclude)
if (rm_bcr) excluded <- c(excluded, BCRgenes.to.exclude)

message(sprintf("Excluded genes — TCR: %d, BCR/Ig: %d",
                length(TCRgenes.to.exclude) * rm_tcr,
                length(BCRgenes.to.exclude) * rm_bcr))

features <- setdiff(all.genes, excluded)

if (assay_name == "SCT") {
  tryCatch(s.obj <- PrepSCTFindMarkers(s.obj), error = function(e) NULL)
}

# DESeq2 requires raw counts and the package loaded
effective_slot <- if (test_use == "DESeq2") "counts" else slot_name

# "scale.data" only holds scaled values for whatever feature subset ScaleData() was
# last run on (typically just the ~2000 variable features used for PCA), not every
# gene — but `features` above lists the assay's full gene universe. Seurat's
# FoldChange.default does `object[features, cells.1]` against the scale.data matrix
# unconditionally, so passing genes it doesn't contain throws "subscript out of
# bounds" for every cluster. FindAllMarkers swallows that per-cluster error into a
# warning just like the DESeq2/MAST failures above, so this used to silently return
# 0 DEGs too. Restrict features to what's actually present in scale.data.
if (effective_slot == "scale.data") {
  scaled_genes <- rownames(GetAssayData(s.obj, assay = assay_name, layer = "scale.data"))
  features <- intersect(features, scaled_genes)
}

if (test_use == "DESeq2") {
  if (!requireNamespace("DESeq2", quietly = TRUE))
    BiocManager::install("DESeq2", ask = FALSE, update = FALSE)
  suppressPackageStartupMessages(library(DESeq2))

  # Seurat's DESeq2 test (Seurat:::DESeq2DETest) calls DESeq2::estimateSizeFactors()
  # with its default "ratio" (median-of-ratios) method, which requires every gene to
  # have a nonzero count in every cell to compute a log geometric mean. Single-cell
  # count matrices are sparse enough that this is essentially never true, so DESeq2
  # errors with "every gene contains at least one zero, cannot compute log geometric
  # means" for every cluster. FindAllMarkers catches that per-cluster error internally
  # and just warns instead of failing, so the run used to silently come back with 0
  # DEGs. Work around the sparsity issue by defaulting estimateSizeFactors() to the
  # "poscounts" estimator (Anders & Huber 2010), which only requires a gene to be
  # nonzero in *some* cells rather than all of them.
  #
  # estimateSizeFactors is an S4 generic owned by BiocGenerics (DESeq2 only supplies
  # the DESeqDataSet method), so it must be overridden via setMethod, not
  # assignInNamespace on DESeq2's own namespace bindings. This container is discarded
  # after the script exits (docker run --rm), so there's no need to restore the
  # original method afterward.
  original_size_factor_method <- selectMethod("estimateSizeFactors", "DESeqDataSet")
  setMethod("estimateSizeFactors", "DESeqDataSet", function(object, type = "poscounts", ...) {
    original_size_factor_method(object, type = type, ...)
  })

  # Separately, Seurat:::DESeq2DETest calls CheckDots(..., fxns = "DESeq2::results")
  # to validate any extra arguments forwarded down from FindMarkers/FindAllMarkers.
  # CheckDots resolves `fxns` entries via utils::argsAnywhere(), which cannot resolve
  # a namespace-qualified string like "DESeq2::results" (it looks for a literal object
  # of that name on the search path) — so whenever any extra args reach DESeq2DETest,
  # CheckDots throws "None of the functions passed could be found" even though the
  # args themselves are perfectly valid. This is a real Seurat bug, independent of the
  # sparsity issue above, that used to be swallowed the same silent way. Patch CheckDots
  # to no-op specifically on that failure while still raising any other error it hits.
  original_check_dots <- Seurat:::CheckDots
  assignInNamespace("CheckDots", function(..., fxns = NULL) {
    tryCatch(original_check_dots(..., fxns = fxns), error = function(e) {
      if (!grepl("None of the functions passed could be found", conditionMessage(e), fixed = TRUE))
        stop(e)
      invisible(NULL)
    })
  }, ns = "Seurat")
}

# MAST isn't in the pipeline image's base package set (unlike DESeq2, which happens
# to be a transitive dependency of something else). Seurat:::MASTDETest immediately
# stops with "Please install MAST..." when it's missing — that error gets caught by
# FindAllMarkers' internal per-cluster tryCatch and demoted to a warning, so the run
# used to come back with 0 DEGs and no visible cause, exactly like the DESeq2 issue
# above. Install on demand so MAST actually works instead of just failing louder.
if (test_use == "MAST") {
  if (!requireNamespace("MAST", quietly = TRUE))
    BiocManager::install("MAST", ask = FALSE, update = FALSE)
  suppressPackageStartupMessages(library(MAST))
}

# Collect warnings raised during the marker search (Seurat re-raises per-cluster DE
# test failures as warnings rather than errors) so we can tell a genuine "no DEGs
# passed the test" result apart from "the test itself failed for every cluster".
de_warnings <- character(0)
run_markers <- function() {
  if (mode == "clusters") {
    FindAllMarkers(s.obj, assay = assay_name, group.by = group_by,
                    test.use = test_use, slot = effective_slot, min.pct = min_pct,
                    features = features, verbose = FALSE)
  } else {
    FindMarkers(s.obj, ident.1 = ident1, ident.2 = if (length(ident2) > 0) ident2 else NULL,
                assay = assay_name, test.use = test_use, slot = effective_slot, min.pct = min_pct,
                features = features, verbose = FALSE) %>%
      tibble::rownames_to_column("gene") %>%
      mutate(cluster = paste(paste(ident1, collapse = "+"), "vs", if (length(ident2) > 0) paste(ident2, collapse = "+") else "others"))
  }
}
markers <- withCallingHandlers(
  run_markers(),
  warning = function(w) {
    de_warnings <<- c(de_warnings, conditionMessage(w))
    invokeRestart("muffleWarning")
  }
)

if (nrow(markers) > 0 && "avg_log2FC" %in% colnames(markers)) {
  markers <- markers %>% mutate(abs_avg_log2FC = abs(avg_log2FC))
} else if (length(de_warnings) > 0) {
  # Every cluster's test failed rather than legitimately finding no DEGs (FindAllMarkers
  # demotes per-cluster failures — missing packages, numerical errors, etc. — to warnings
  # instead of raising) — surface it as a real error instead of returning an empty,
  # misleadingly-successful result. Not test-specific: applies to any test.use.
  stop(test_use, " failed and returned no markers. Underlying error(s): ",
       paste(unique(de_warnings), collapse = " | "))
} else {
  markers <- data.frame()
}

result <- list(
  markers       = markers,
  excluded_tcr  = if (rm_tcr) as.list(TCRgenes.to.exclude) else list(),
  excluded_bcr  = if (rm_bcr) as.list(BCRgenes.to.exclude) else list(),
  species       = if (is_human) "human" else "mouse"
)
cat(toJSON(result, auto_unbox = TRUE, na = "null"))
