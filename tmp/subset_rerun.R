gc()
rm(list = ls())

path.to.pipeline.src <- "/home/hieunguyen/CRC1382/src_2023/src_pipeline/scRNA_GEX_pipeline_SeuratV5"
path2src <- file.path(path.to.pipeline.src, "processes_src")
source(file.path(path2src, "import_libraries.R"))
source(file.path(path2src, "helper_functions.R"))

outdir <- "/home/hieunguyen/CRC1382/outdir"

PROJECT <- "260422_Soussan_P79_SeuratV5"

analysis.round <- "1st_round"
sample.id <- "P79"

path.to.main.output <- file.path(outdir, PROJECT, "data_analysis")
path.to.01.output <- file.path(path.to.main.output, "01_output")
path.to.02.output <- file.path(path.to.main.output, "02_output")
path.to.03.output <- file.path(path.to.main.output, "03_output")
path.to.04.output <- file.path(path.to.main.output, "04_output")
dir.create(path.to.04.output, showWarnings = FALSE, recursive = TRUE)

path.to.main.src <- "/home/hieunguyen/CRC1382/src_2025/260422_Soussan"

subset.version <- "v0.1"

rerun <- TRUE

if (file.exists(file.path(path.to.04.output, "plasmaCells.reAanalysis.rds")) == FALSE | rerun == TRUE){
  # ***** read the seurat object with VDJ information from 02_output *****
  s.obj <- readRDS(file.path(path.to.04.output, sprintf("plasmaCells_%s.rds", subset.version)))
  
  # ***** re analysis after sub-clustering
  num.PCA <- 25
  num.PC.used.in.UMAP <- 25
  num.PC.used.in.Clustering <- 25
  regressOut_mode <- NULL
  features_to_regressOut <- NULL
  use.sctransform <- TRUE
  vars.to.regress <- c("percent.mt")
  num.dim.integration <- 25 
  num.dim.cluster <- 25
  my_random_seed <- 42
  cluster.resolution <- 0.5
  
  
  # ***** TCR AND BCR GENES *****
  TR_genes_patterns <- c("Trav", "Traj", "Trac", "Trbv", "Trbd", "Trbj", "Trbc",
                         "Trgv", "Trgj", "Trgc", "Trdv", "Trdc", "Trdj") 
  BR_genes_patterns <- c("Ighv", "Ighd", "Ighj", "Ighc", "Igkv",
                         "Igkj", "Igkc", "Iglv", "Iglj", "Iglc")
  TR_genes_patterns <- toupper(TR_genes_patterns)
  BR_genes_patterns <- toupper(BR_genes_patterns)
  
  all.genes <- row.names(s.obj)
  TCRgenes.to.exclude <- unlist(lapply(all.genes, function(x){
    if (substr(x, 1, 4) %in% TR_genes_patterns){
      return(x)
    } else {
      return(NA)
    }
  }))
  TCRgenes.to.exclude <- subset(TCRgenes.to.exclude, is.na(TCRgenes.to.exclude) == FALSE)
  
  ##### remove BCR genes 
  BCRgenes.to.exclude <- unlist(lapply(all.genes, function(x){
    if (substr(x, 1, 4) %in% BR_genes_patterns){
      return(x)
    } else {
      return(NA)
    }
  }))
  BCRgenes.to.exclude <- subset(BCRgenes.to.exclude, is.na(BCRgenes.to.exclude) == FALSE)
  remove.genes <- c(TCRgenes.to.exclude, BCRgenes.to.exclude)
  
  # *****
  pca_reduction_name <- "SCT_PCA"
  umap_reduction_name <- "SCT_UMAP"
  
  DefaultAssay(s.obj) <- "RNA"
  s.obj <- DietSeurat(s.obj)
  
  s.obj <- SCTransform(s.obj, vars.to.regress = vars.to.regress, verbose = FALSE)
  s.obj <- RunPCA(s.obj, npcs = num.PCA, verbose = FALSE, reduction.name=pca_reduction_name, 
                  features = setdiff(VariableFeatures(s.obj), remove.genes))
  s.obj <- RunUMAP(s.obj, reduction = pca_reduction_name,
                   dims = 1:num.PC.used.in.UMAP, reduction.name=umap_reduction_name,
                   seed.use = my_random_seed, umap.method = "uwot")
  s.obj <- FindNeighbors(s.obj, reduction = pca_reduction_name, dims = 1:num.PC.used.in.Clustering)
  s.obj <- FindClusters(s.obj, resolution = cluster.resolution, random.seed = 0)
  
  DimPlot(object = s.obj, reduction = "SCT_UMAP", label = TRUE, label.box = TRUE, group.by = "seurat_clusters")
  
  saveRDS(s.obj, file.path(path.to.04.output, sprintf("plasmaCells_%s.processed.rds", subset.version)))
} 
