process UMAP_CLUSTERING {
    tag "${sample}"
    publishDir "${params.outdir}/s8_umap_clustering",               mode: "copy"

    input:
    tuple val(sample), path(seurat_rds)
    val  use_sctransform
    val  num_PCA
    val  num_PC_used_in_UMAP
    val  num_PC_used_in_Clustering
    val  cluster_resolution
    val  vars_to_regress
    val  remove_genes

    output:
    tuple val(sample), path("${sample}_s8.rds"), emit: seurat_rds

    script:
    """
    cat > run_s8.R << 'REOF'
suppressPackageStartupMessages({
  library(Seurat)
  library(harmony)
  library(stringr)
  library(optparse)
})

option_list <- list(
  make_option("--rds",                      type = "character"),
  make_option("--sample",                   type = "character", default = "sample"),
  make_option("--use_sctransform",          type = "character", default = "false"),
  make_option("--num_PCA",                  type = "integer",   default = 50L),
  make_option("--num_PC_used_in_UMAP",      type = "integer",   default = 30L),
  make_option("--num_PC_used_in_Clustering",type = "integer",   default = 30L),
  make_option("--cluster_resolution",       type = "double",    default = 0.5),
  make_option("--vars_to_regress",          type = "character", default = "percent.mt"),
  make_option("--remove_genes",             type = "character", default = "none")
)
opt <- parse_args(OptionParser(option_list = option_list))

use.sctransform          <- tolower(opt\$use_sctransform) == "true"
num.PCA                  <- opt\$num_PCA
num.PC.used.in.UMAP      <- opt\$num_PC_used_in_UMAP
num.PC.used.in.Clustering<- opt\$num_PC_used_in_Clustering
cluster.resolution       <- opt\$cluster_resolution

vars.to.regress <- if (opt\$vars_to_regress == "none") NULL else
                   trimws(strsplit(opt\$vars_to_regress, ",")[[1]])

remove.genes <- if (opt\$remove_genes == "none") NULL else
                trimws(strsplit(opt\$remove_genes, ",")[[1]])

s.obj <- readRDS(opt\$rds)

s8.integration.and.clustering <- function(s.obj,
                                           use.sctransform,
                                           num.PCA,
                                           num.PC.used.in.UMAP,
                                           num.PC.used.in.Clustering,
                                           cluster.resolution,
                                           vars.to.regress,
                                           remove.genes) {

  s.obj[["RNA"]] <- split(s.obj[["RNA"]], f = s.obj\$name)
  DefaultAssay(s.obj) <- "RNA"

  if (use.sctransform) {
    s.obj <- SCTransform(s.obj, vars.to.regress = vars.to.regress, verbose = FALSE)
    normalization.method <- "SCT"
  } else {
    s.obj <- NormalizeData(s.obj, normalization.method = "LogNormalize")
    s.obj <- FindVariableFeatures(s.obj, selection.method = "vst")
    s.obj <- ScaleData(s.obj, features = rownames(s.obj), vars.to.regress = vars.to.regress)
    normalization.method <- "LogNormalize"
  }

  if (!is.null(remove.genes)) {
    s.obj <- RunPCA(s.obj,
                    npcs = num.PCA,
                    verbose = TRUE,
                    reduction.name = "RNA_PCA",
                    features = setdiff(VariableFeatures(s.obj), remove.genes))
  } else {
    s.obj <- RunPCA(s.obj, npcs = num.PCA, verbose = TRUE, reduction.name = "RNA_PCA")
  }

  s.obj <- RunUMAP(s.obj,
                   dims = 1:num.PC.used.in.UMAP,
                   reduction = "RNA_PCA",
                   reduction.name = "umap.unintegrated")
  message("UMAP (unintegrated) finished.")

  message("Integrating with CCA ...")
  s.obj <- IntegrateLayers(
    object = s.obj,
    method = CCAIntegration,
    orig.reduction = "RNA_PCA",
    new.reduction = "integrated.cca",
    verbose = TRUE,
    normalization.method = normalization.method
  )

  message("Integrating with RPCA ...")
  s.obj <- IntegrateLayers(
    object = s.obj,
    method = RPCAIntegration,
    orig.reduction = "RNA_PCA",
    new.reduction = "integrated.rpca",
    verbose = TRUE,
    normalization.method = normalization.method
  )

  message("Integrating with Harmony ...")
  s.obj <- IntegrateLayers(
    object = s.obj,
    method = HarmonyIntegration,
    orig.reduction = "RNA_PCA",
    new.reduction = "harmony",
    verbose = TRUE,
    normalization.method = normalization.method
  )

  message("All integrations finished.")

  all.reductions <- c("integrated.cca", "integrated.rpca", "harmony")

  for (selected.reduction in all.reductions) {
    new.reduction.name <- str_replace(selected.reduction, "integrated\\.", "")
    s.obj <- FindNeighbors(s.obj,
                           dims = 1:num.PC.used.in.Clustering,
                           reduction = selected.reduction)
    s.obj <- FindClusters(s.obj,
                          resolution = cluster.resolution,
                          cluster.name = sprintf("%s.cluster.%s",
                                                 new.reduction.name,
                                                 cluster.resolution))
    s.obj <- RunUMAP(s.obj,
                     reduction = selected.reduction,
                     dims = 1:num.PC.used.in.UMAP,
                     reduction.name = sprintf("%s_UMAP", new.reduction.name))
    message("Done: ", selected.reduction)
  }

  DefaultAssay(s.obj) <- "RNA"
  s.obj <- JoinLayers(s.obj)
  if ("SCT" %in% Assays(s.obj)) DefaultAssay(s.obj) <- "SCT"

  s.obj\$seurat_clusters <- NULL
  return(s.obj)
}

s.obj <- s8.integration.and.clustering(
  s.obj,
  use.sctransform           = use.sctransform,
  num.PCA                   = num.PCA,
  num.PC.used.in.UMAP       = num.PC.used.in.UMAP,
  num.PC.used.in.Clustering = num.PC.used.in.Clustering,
  cluster.resolution        = cluster.resolution,
  vars.to.regress           = vars.to.regress,
  remove.genes              = remove.genes
)

saveRDS(s.obj, paste0(opt\$sample, "_s8.rds"))
message("Step 8 complete.")
REOF

    Rscript run_s8.R \\
        --rds                       "${seurat_rds}" \\
        --sample                    "${sample}" \\
        --use_sctransform           "${use_sctransform}" \\
        --num_PCA                   ${num_PCA} \\
        --num_PC_used_in_UMAP       ${num_PC_used_in_UMAP} \\
        --num_PC_used_in_Clustering ${num_PC_used_in_Clustering} \\
        --cluster_resolution        ${cluster_resolution} \\
        --vars_to_regress           "${vars_to_regress}" \\
        --remove_genes              "${remove_genes}"
    """
}
