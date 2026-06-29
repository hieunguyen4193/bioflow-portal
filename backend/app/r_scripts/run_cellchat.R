suppressPackageStartupMessages(library(rmarkdown))

args                <- commandArgs(trailingOnly = TRUE)
rds_path            <- args[1]
outputdir           <- args[2]
sample_id           <- if (length(args) >= 3 && nchar(args[3]) > 0) args[3] else "ALL"
filter10cells       <- if (length(args) >= 4 && nchar(args[4]) > 0) args[4] else "NoFilter"
reduction_name      <- if (length(args) >= 5 && nchar(args[5]) > 0) args[5] else "umap"
cluster_name        <- if (length(args) >= 6 && nchar(args[6]) > 0) args[6] else "seurat_clusters"
input_spec          <- if (length(args) >= 7 && nchar(args[7]) > 0) args[7] else "Human"
rmd_path            <- args[8]   # path to Rmd inside the container

dir.create(outputdir, showWarnings = FALSE, recursive = TRUE)

safe_name <- gsub("[^A-Za-z0-9_-]", "_", sample_id)
output_html <- file.path(outputdir, sprintf("CellChat_%s_%s.html", safe_name, filter10cells))

message(sprintf("Rendering CellChat report for sample '%s'...", sample_id))
message(sprintf("  RDS:       %s", rds_path))
message(sprintf("  Reduction: %s", reduction_name))
message(sprintf("  Cluster:   %s", cluster_name))
message(sprintf("  Species:   %s", input_spec))
message(sprintf("  Output:    %s", output_html))

rmarkdown::render(
  input         = rmd_path,
  output_file   = output_html,
  output_dir    = outputdir,
  knit_root_dir = outputdir,
  params = list(
    sample.id           = sample_id,
    path.to.s.obj       = rds_path,
    path.to.save.output = outputdir,
    filter10cells       = filter10cells,
    reduction.name      = reduction_name,
    cluster.name        = cluster_name,
    input.spec          = input_spec
  ),
  envir = new.env(parent = globalenv())
)

cat(jsonlite::toJSON(list(html = output_html), auto_unbox = TRUE))
