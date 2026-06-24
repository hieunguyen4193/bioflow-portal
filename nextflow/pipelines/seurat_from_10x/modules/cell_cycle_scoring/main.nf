process CELL_CYCLE_SCORING {
    tag "${sample}"
    publishDir "${params.outdir}/s5_cell_cycle",               mode: "copy"
    publishDir "${params.outdir}/intermediates/s5_cell_cycle", mode: "copy", pattern: "*_s5.rds"

    input:
    tuple val(sample), path(seurat_rds)
    val  use_sctransform
    val  vars_to_regress

    output:
    tuple val(sample), path("*_s5.rds"), emit: seurat_rds
    path "cell_cycle_summary.csv",       emit: summary
    path "*.png",                        emit: plots, optional: true

    script:
    """
    cat > run_cell_cycle.R << 'REOF'
suppressPackageStartupMessages({
  library(Seurat)
  library(ggplot2)
  library(optparse)
})

option_list <- list(
  make_option("--rds",             type = "character"),
  make_option("--sample",          type = "character", default = "sample"),
  make_option("--use_sctransform", type = "logical",   default = FALSE),
  make_option("--vars_to_regress", type = "character", default = "percent.mt")
)
opt <- parse_args(OptionParser(option_list = option_list))

s.obj <- readRDS(opt\$rds)
vars.to.regress <- trimws(strsplit(opt\$vars_to_regress, ",")[[1]])

# ── Preprocessing + cell cycle scoring function ───────────────────────────
s5.preprocess.before.cellCycle.scoring <- function(s.obj,
                                                   use.sctransform  = FALSE,
                                                   vars.to.regress  = c("percent.mt"),
                                                   PROJECT          = "sample") {

  # ── QC metrics (recalculate in case not present) ────────────────────────
  s.obj[["percent.mt"]]   <- PercentageFeatureSet(s.obj, pattern = "^mt-|^MT-")
  s.obj[["percent.ribo"]] <- PercentageFeatureSet(s.obj, pattern = "^Rpl|^Rps|^RPL|^RPS")

  mt.genes   <- grep("^mt-|^MT-",         rownames(s.obj), value = TRUE)
  ribo.genes <- grep("^Rpl|^Rps|^RPL|^RPS", rownames(s.obj), value = TRUE)
  s.obj[["percent.exclude"]] <- PercentageFeatureSet(s.obj,
                                  features = c(mt.genes, ribo.genes))

  # ── Normalisation / scaling ─────────────────────────────────────────────
  if (isTRUE(use.sctransform)) {
    s.obj <- SCTransform(s.obj, vars.to.regress = vars.to.regress, verbose = FALSE)
  } else {
    s.obj <- NormalizeData(s.obj)
    s.obj <- FindVariableFeatures(s.obj, selection.method = "vst")
    s.obj <- ScaleData(s.obj, features = rownames(s.obj))
  }

  # ── Match cc.genes to this dataset (case-insensitive) ──────────────────
  all.genes <- rownames(s.obj)

  s.genes <- paste0("^", cc.genes\$s.genes, "\$", collapse = "|")
  s.genes <- all.genes[grepl(s.genes, all.genes, ignore.case = TRUE)]

  g2m.genes <- paste0("^", cc.genes\$g2m.genes, "\$", collapse = "|")
  g2m.genes <- all.genes[grepl(g2m.genes, all.genes, ignore.case = TRUE)]

  message(sprintf("Cell cycle genes found — S: %d, G2M: %d", length(s.genes), length(g2m.genes)))

  # ── Score cell cycle ────────────────────────────────────────────────────
  s.obj <- CellCycleScoring(s.obj,
    s.features   = s.genes,
    g2m.features = g2m.genes,
    set.ident    = TRUE)

  return(s.obj)
}

s.obj <- s5.preprocess.before.cellCycle.scoring(
  s.obj,
  use.sctransform = opt\$use_sctransform,
  vars.to.regress = vars.to.regress,
  PROJECT         = opt\$sample
)

# ── Plots ──────────────────────────────────────────────────────────────────
# PCA coloured by phase (requires PCA to be run first)
s.obj <- RunPCA(s.obj, features = c(
  rownames(s.obj)[grepl("^S\\\\.", rownames(s.obj))],  # fallback
  rownames(s.obj)[grepl("^G2M\\\\.", rownames(s.obj))]
), verbose = FALSE)

p_phase <- DimPlot(s.obj, group.by = "Phase") +
  ggtitle(sprintf("%s — Cell cycle phase (PCA)", opt\$sample))
ggsave("cell_cycle_phase_pca.png", p_phase, width = 7, height = 6, dpi = 150)

p_vln <- VlnPlot(s.obj, features = c("S.Score", "G2M.Score"), ncol = 2, pt.size = 0) +
  ggtitle(sprintf("%s — S / G2M scores", opt\$sample))
ggsave("cell_cycle_scores_violin.png", p_vln, width = 10, height = 5, dpi = 150)

# ── Summary table ──────────────────────────────────────────────────────────
phase_tbl <- as.data.frame(table(s.obj\$name, s.obj\$Phase))
colnames(phase_tbl) <- c("sample", "phase", "n_cells")
write.csv(phase_tbl, "cell_cycle_summary.csv", row.names = FALSE)

saveRDS(s.obj, paste0(opt\$sample, "_s5.rds"))
message("Step 5 done.")
REOF

    Rscript run_cell_cycle.R \\
        --rds             ${seurat_rds} \\
        --sample          "${sample}" \\
        --use_sctransform ${use_sctransform} \\
        --vars_to_regress "${vars_to_regress}"
    """
}
