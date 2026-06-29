suppressPackageStartupMessages({
  library(dplyr)
  library(jsonlite)
  library(clusterProfiler)
  library(org.Hs.eg.db)
  library(org.Mm.eg.db)
  library(msigdbr)
})

args         <- commandArgs(trailingOnly = TRUE)
csv_path     <- args[1]
outputdir    <- args[2]
pval_cutoff  <- as.numeric(args[3])
species      <- if (length(args) >= 4 && nchar(args[4]) > 0) args[4] else "auto"

dir.create(outputdir, showWarnings = FALSE, recursive = TRUE)

# ── Species config ────────────────────────────────────────────────────────────
species_db   <- list(hsa = org.Hs.eg.db, mmu = org.Mm.eg.db)
species_full <- list(hsa = "Homo sapiens", mmu = "Mus musculus")

# ── Load gene list ────────────────────────────────────────────────────────────
fulldf <- read.csv(csv_path, stringsAsFactors = FALSE)
if ("X" %in% colnames(fulldf)) fulldf <- subset(fulldf, select = -c(X))

# Normalize column names from either DGE output format
col_map <- list(
  gene  = c("gene"),
  logFC = c("logFC", "avg_log2FC"),
  pval  = c("pval", "p_val"),
  padj  = c("padj", "p_val_adj")
)
for (target in names(col_map)) {
  found <- intersect(col_map[[target]], colnames(fulldf))[1]
  if (!is.na(found) && found != target) fulldf[[target]] <- fulldf[[found]]
}
fulldf <- fulldf[!is.na(fulldf$gene) & !is.na(fulldf$logFC) & !is.na(fulldf$padj), ]

# ── Auto-detect species from gene name casing ────────────────────────────────
if (species == "auto") {
  sample_genes <- head(fulldf$gene[nchar(fulldf$gene) >= 3], 200)
  pct_upper    <- mean(sample_genes == toupper(sample_genes), na.rm = TRUE)
  species      <- if (pct_upper > 0.5) "hsa" else "mmu"
  message(sprintf("Auto-detected species: %s (%.0f%% uppercase gene names)", species, pct_upper * 100))
}
org_db <- species_db[[species]]

# ── Convert gene symbols → ENTREZ IDs ────────────────────────────────────────
convertdf <- tryCatch(
  bitr(fulldf$gene, fromType = "SYMBOL", toType = "ENTREZID", OrgDb = org_db),
  error = function(e) data.frame(SYMBOL = character(), ENTREZID = character())
)
fulldf <- merge(fulldf, convertdf, by.x = "gene", by.y = "SYMBOL", all.x = FALSE)
fulldf <- fulldf[!duplicated(fulldf$gene), ]

# ── Sort by logFC descending (required for GSEA ranked list) ─────────────────
fulldf <- fulldf[order(fulldf$logFC, decreasing = TRUE), ]

convert_geneids <- function(id_str) {
  ids <- strsplit(id_str, "/")[[1]]
  syms <- convertdf$SYMBOL[match(ids, convertdf$ENTREZID)]
  paste(syms[!is.na(syms)], collapse = "/")
}

# ── Gene subsets ──────────────────────────────────────────────────────────────
sig_all  <- subset(fulldf, padj <= pval_cutoff)$gene
sig_up   <- subset(fulldf, padj <= pval_cutoff & logFC > 0)$gene
sig_down <- subset(fulldf, padj <= pval_cutoff & logFC < 0)$gene

sig_all_ez  <- as.character(subset(fulldf, padj <= pval_cutoff)$ENTREZID)
sig_up_ez   <- as.character(subset(fulldf, padj <= pval_cutoff & logFC > 0)$ENTREZID)
sig_down_ez <- as.character(subset(fulldf, padj <= pval_cutoff & logFC < 0)$ENTREZID)

ranked_list <- fulldf %>% arrange(desc(logFC))
gene_list_ez <- ranked_list$logFC
names(gene_list_ez) <- as.character(ranked_list$ENTREZID)

gene_list_sym <- ranked_list$logFC
names(gene_list_sym) <- ranked_list$gene

# ── Helper: safe enrichment → clean data.frame ───────────────────────────────
safe_df <- function(obj, convert_entrez = FALSE) {
  if (is.null(obj)) return(data.frame(status = "No significant results"))
  df <- tryCatch(as.data.frame(obj), error = function(e) data.frame(status = "Error"))
  if (nrow(df) == 0) return(data.frame(status = "No significant results"))
  if (convert_entrez && "geneID" %in% colnames(df)) {
    df <- df %>% rowwise() %>% mutate(geneID = convert_geneids(geneID)) %>% ungroup()
  }
  if ("core_enrichment" %in% colnames(df)) {
    df <- df %>% rowwise() %>% mutate(geneID = convert_geneids(core_enrichment)) %>% ungroup()
    df <- subset(df, select = -c(core_enrichment))
  }
  df %>% mutate_if(is.numeric, round, digits = 6)
}

output <- list()

# ── ORA — GO ─────────────────────────────────────────────────────────────────
message("ORA GO (full)...")
output[["ORA.FULL.GO"]] <- safe_df(tryCatch(
  enrichGO(sig_all, OrgDb = org_db, ont = "ALL", pvalueCutoff = pval_cutoff,
           qvalueCutoff = pval_cutoff, readable = TRUE, keyType = "SYMBOL", pAdjustMethod = "BH"),
  error = function(e) NULL))

message("ORA GO (up)...")
output[["ORA.UP.GO"]] <- safe_df(tryCatch(
  enrichGO(sig_up, OrgDb = org_db, ont = "ALL", pvalueCutoff = pval_cutoff,
           qvalueCutoff = pval_cutoff, readable = TRUE, keyType = "SYMBOL", pAdjustMethod = "BH"),
  error = function(e) NULL))

message("ORA GO (down)...")
output[["ORA.DOWN.GO"]] <- safe_df(tryCatch(
  enrichGO(sig_down, OrgDb = org_db, ont = "ALL", pvalueCutoff = pval_cutoff,
           qvalueCutoff = pval_cutoff, readable = TRUE, keyType = "SYMBOL", pAdjustMethod = "BH"),
  error = function(e) NULL))

# ── ORA — KEGG ───────────────────────────────────────────────────────────────
message("ORA KEGG (full)...")
output[["ORA.FULL.KEGG"]] <- safe_df(tryCatch(
  enrichKEGG(sig_all_ez, organism = species, pvalueCutoff = pval_cutoff, qvalueCutoff = pval_cutoff),
  error = function(e) NULL), convert_entrez = TRUE)

message("ORA KEGG (up)...")
output[["ORA.UP.KEGG"]] <- safe_df(tryCatch(
  enrichKEGG(sig_up_ez, organism = species, pvalueCutoff = pval_cutoff, qvalueCutoff = pval_cutoff),
  error = function(e) NULL), convert_entrez = TRUE)

message("ORA KEGG (down)...")
output[["ORA.DOWN.KEGG"]] <- safe_df(tryCatch(
  enrichKEGG(sig_down_ez, organism = species, pvalueCutoff = pval_cutoff, qvalueCutoff = pval_cutoff),
  error = function(e) NULL), convert_entrez = TRUE)

# ── ORA — WikiPathways ───────────────────────────────────────────────────────
message("ORA WikiPathways (full)...")
output[["ORA.FULL.WP"]] <- safe_df(tryCatch(
  clusterProfiler::enrichWP(sig_all_ez, organism = species_full[[species]],
                             pvalueCutoff = pval_cutoff, pAdjustMethod = "fdr"),
  error = function(e) NULL), convert_entrez = TRUE)

message("ORA WikiPathways (up)...")
output[["ORA.UP.WP"]] <- safe_df(tryCatch(
  clusterProfiler::enrichWP(sig_up_ez, organism = species_full[[species]],
                             pvalueCutoff = pval_cutoff, pAdjustMethod = "fdr"),
  error = function(e) NULL), convert_entrez = TRUE)

message("ORA WikiPathways (down)...")
output[["ORA.DOWN.WP"]] <- safe_df(tryCatch(
  clusterProfiler::enrichWP(sig_down_ez, organism = species_full[[species]],
                             pvalueCutoff = pval_cutoff, pAdjustMethod = "fdr"),
  error = function(e) NULL), convert_entrez = TRUE)

# ── GSEA — GO ────────────────────────────────────────────────────────────────
message("GSEA GO...")
output[["GSEA.GO"]] <- safe_df(tryCatch(
  gseGO(gene_list_sym, OrgDb = org_db, ont = "ALL", keyType = "SYMBOL",
        minGSSize = 10, maxGSSize = 500, pvalueCutoff = pval_cutoff, verbose = FALSE, seed = TRUE),
  error = function(e) NULL))

# ── GSEA — KEGG ──────────────────────────────────────────────────────────────
message("GSEA KEGG...")
output[["GSEA.KEGG"]] <- safe_df(tryCatch(
  gseKEGG(gene_list_ez, organism = species, minGSSize = 10, maxGSSize = 500,
          pvalueCutoff = pval_cutoff, verbose = FALSE, seed = TRUE),
  error = function(e) NULL), convert_entrez = TRUE)

# ── GSEA — WikiPathways ──────────────────────────────────────────────────────
message("GSEA WikiPathways...")
output[["GSEA.WP"]] <- safe_df(tryCatch(
  gseWP(gene_list_ez, organism = species_full[[species]], minGSSize = 10,
        maxGSSize = 500, pvalueCutoff = pval_cutoff, verbose = FALSE, seed = TRUE),
  error = function(e) NULL), convert_entrez = TRUE)

# ── MSigDB — all available collections for the detected species ───────────────
# Human: H, C1–C9   Mouse: H, M1–M8
msigdb_cats <- if (species == "hsa") {
  c("H", "C1", "C2", "C3", "C4", "C5", "C6", "C7", "C8", "C9")
} else {
  c("H", "M1", "M2", "M3", "M4", "M5", "M6", "M7", "M8")
}

# List all categories actually available in the installed msigdbr for this species
available_cats <- tryCatch({
  all_sets <- msigdbr_collections()
  unique(all_sets$gs_cat)
}, error = function(e) character(0))
message(sprintf("msigdbr available categories for %s: %s",
                species_full[[species]], paste(sort(available_cats), collapse = ", ")))

for (cat in msigdb_cats) {
  message(sprintf("MSigDB %s: fetching gene sets...", cat))
  m_t2g <- tryCatch({
    raw <- msigdbr(species = species_full[[species]], category = cat)
    message(sprintf("  %s: %d rows, %d gene sets", cat, nrow(raw), length(unique(raw$gs_name))))
    raw %>% dplyr::select(gs_name, entrez_gene) %>%
      dplyr::mutate(entrez_gene = as.character(entrez_gene)) %>%
      dplyr::filter(!is.na(entrez_gene))
  }, error = function(e) {
    message(sprintf("  %s: FAILED — %s", cat, conditionMessage(e)))
    NULL
  })

  if (!is.null(m_t2g) && nrow(m_t2g) > 0) {
    message(sprintf("  %s: running ORA...", cat))
    output[[paste0("ORA.FULL.MSigDB.", cat)]] <- safe_df(tryCatch(
      enricher(sig_all_ez, TERM2GENE = m_t2g, pvalueCutoff = pval_cutoff),
      error = function(e) { message(sprintf("  ORA %s error: %s", cat, e$message)); NULL }),
      convert_entrez = TRUE)

    message(sprintf("  %s: running GSEA...", cat))
    output[[paste0("GSEA.MSigDB.", cat)]] <- safe_df(tryCatch(
      GSEA(gene_list_ez, TERM2GENE = m_t2g, pvalueCutoff = pval_cutoff, verbose = FALSE, seed = TRUE),
      error = function(e) { message(sprintf("  GSEA %s error: %s", cat, e$message)); NULL }),
      convert_entrez = TRUE)
    message(sprintf("  %s: done.", cat))
  } else {
    message(sprintf("  %s: no gene sets returned — skipping.", cat))
  }
}

# ── Save and output JSON ──────────────────────────────────────────────────────
saveRDS(output, file.path(outputdir, "pathway_results.rds"))
cat(toJSON(output, auto_unbox = TRUE, na = "null"))
