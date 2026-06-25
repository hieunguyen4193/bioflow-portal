process CELL_CYCLE_SCORING_S6 {
    tag "${sample}"
    publishDir "${params.outdir}/s6_cell_cycle_scoring",               mode: "copy"

    input:
    tuple val(sample), path(seurat_rds)
    val  mode

    output:
    tuple val(sample), path("*_s6.rds"), emit: seurat_rds
    path "cell_cycle_s6_summary.csv",    emit: summary
    path "*.png",                        emit: plots, optional: true

    script:
    """
    cat > run_cell_cycle_s6.R << 'REOF'
suppressPackageStartupMessages({
  library(Seurat)
  library(ggplot2)
  library(optparse)
})

option_list <- list(
  make_option("--rds",    type = "character"),
  make_option("--sample", type = "character", default = "sample"),
  make_option("--mode",   type = "character", default = "gene_name")
)
opt <- parse_args(OptionParser(option_list = option_list))

# helper operator
`%ni%` <- function(x, y) !x %in% y

s.obj <- readRDS(opt\$rds)

# ── Cell cycle scoring function ────────────────────────────────────────────
s6.cellCycleScoring <- function(s.obj, mode = "gene_name", PROJECT = "sample") {

  s.obj <- ScaleData(s.obj, features = rownames(s.obj))

  if (mode == "gene_name") {
    all.genes <- rownames(s.obj)

    s.genes <- paste0("^", cc.genes\$s.genes, "\$", collapse = "|")
    s.genes <- all.genes[grepl(s.genes, all.genes, ignore.case = TRUE)]

    g2m.genes <- paste0("^", cc.genes\$g2m.genes, "\$", collapse = "|")
    g2m.genes <- all.genes[grepl(g2m.genes, all.genes, ignore.case = TRUE)]

    message(sprintf("Gene-name mode — S genes: %d, G2M genes: %d",
                    length(s.genes), length(g2m.genes)))

    s.obj <- CellCycleScoring(s.obj,
      s.features   = s.genes,
      g2m.features = g2m.genes,
      set.ident    = TRUE)

  } else if (mode == "ensembl") {
    suppressPackageStartupMessages(library(org.Hs.eg.db))

    cc.genes.ensembl <- list()
    cc.genes.ensembl\$s.genes <- mapIds(org.Hs.eg.db,
      keys     = cc.genes\$s.genes,
      column   = "ENSEMBL",
      keytype  = "SYMBOL",
      multiVals = "first")

    cc.genes.ensembl\$g2m.genes <- mapIds(org.Hs.eg.db,
      keys     = cc.genes\$g2m.genes,
      column   = "ENSEMBL",
      keytype  = "SYMBOL",
      multiVals = "first")

    # drop NAs from mapping
    cc.genes.ensembl\$s.genes   <- na.omit(cc.genes.ensembl\$s.genes)
    cc.genes.ensembl\$g2m.genes <- na.omit(cc.genes.ensembl\$g2m.genes)

    message(sprintf("Ensembl mode — S genes: %d, G2M genes: %d",
                    length(cc.genes.ensembl\$s.genes),
                    length(cc.genes.ensembl\$g2m.genes)))

    s.obj <- CellCycleScoring(s.obj,
      s.features   = cc.genes.ensembl\$s.genes,
      g2m.features = cc.genes.ensembl\$g2m.genes,
      set.ident    = TRUE)

  } else {
    stop("mode must be 'gene_name' or 'ensembl'. Got: ", mode)
  }

  # ── Extra scores ──────────────────────────────────────────────────────────
  s.obj\$G1.Score      <- 1 - s.obj\$S.Score - s.obj\$G2M.Score
  s.obj\$CC.Difference <- s.obj\$S.Score - s.obj\$G2M.Score

  # ── Ensure QC metrics present ─────────────────────────────────────────────
  if ("percent.mt" %ni% names(s.obj@meta.data))
    s.obj[["percent.mt"]]   <- PercentageFeatureSet(s.obj, pattern = "^mt-|^MT-")
  if ("percent.ribo" %ni% names(s.obj@meta.data))
    s.obj[["percent.ribo"]] <- PercentageFeatureSet(s.obj, pattern = "^Rpl|^Rps|^RPL|^RPS")

  return(s.obj)
}

s.obj <- s6.cellCycleScoring(s.obj, mode = opt\$mode, PROJECT = opt\$sample)

# ── Plots ──────────────────────────────────────────────────────────────────
p_scores <- VlnPlot(s.obj,
  features = c("S.Score", "G2M.Score", "G1.Score", "CC.Difference"),
  ncol = 2, pt.size = 0, group.by = "Phase") +
  ggtitle(sprintf("%s — Cell cycle scores by phase", opt\$sample))
ggsave("cc_scores_by_phase.png", p_scores, width = 12, height = 8, dpi = 150)

p_scatter <- FeatureScatter(s.obj, feature1 = "S.Score", feature2 = "G2M.Score",
                             group.by = "Phase") +
  ggtitle(sprintf("%s — S vs G2M score", opt\$sample))
ggsave("cc_s_vs_g2m_scatter.png", p_scatter, width = 7, height = 6, dpi = 150)

# ── Summary ────────────────────────────────────────────────────────────────
phase_tbl <- as.data.frame(table(s.obj\$name, s.obj\$Phase))
colnames(phase_tbl) <- c("sample", "phase", "n_cells")

score_summary <- aggregate(
  cbind(S.Score, G2M.Score, G1.Score, CC.Difference) ~ name,
  data = s.obj@meta.data,
  FUN  = median
)
colnames(score_summary)[1] <- "sample"

write.csv(merge(phase_tbl, score_summary, by = "sample", all.x = TRUE),
          "cell_cycle_s6_summary.csv", row.names = FALSE)

saveRDS(s.obj, paste0(opt\$sample, "_s6.rds"))
message("Step 6 done.")
REOF

    Rscript run_cell_cycle_s6.R \\
        --rds    "${seurat_rds}" \\
        --sample "${sample}" \\
        --mode   "${mode}"
    """
}
