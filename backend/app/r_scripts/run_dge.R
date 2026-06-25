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
ident1       <- if (length(args) >= 7) args[7] else ""
ident2       <- if (length(args) >= 8) args[8] else ""
rm_tcr       <- if (length(args) >= 9) args[9] == "true" else TRUE
rm_bcr       <- if (length(args) >= 10) args[10] == "true" else TRUE

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

if (mode == "clusters") {
  markers <- FindAllMarkers(s.obj, assay = assay_name, group.by = group_by,
                            test.use = test_use, slot = slot_name,
                            features = features, verbose = FALSE)
} else {
  markers <- FindMarkers(s.obj, ident.1 = ident1, ident.2 = if (nchar(ident2) > 0) ident2 else NULL,
                         assay = assay_name, test.use = test_use, slot = slot_name,
                         features = features, verbose = FALSE) %>%
    tibble::rownames_to_column("gene") %>%
    mutate(cluster = paste(ident1, "vs", ident2))
}

if (nrow(markers) > 0 && "avg_log2FC" %in% colnames(markers)) {
  markers <- markers %>% mutate(abs_avg_log2FC = abs(avg_log2FC))
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
