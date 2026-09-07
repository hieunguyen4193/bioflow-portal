suppressPackageStartupMessages(library(Seurat))
suppressPackageStartupMessages(library(jsonlite))

# Lightweight companion to extract_seurat.R for the admin cache-management page:
# reports only assay/slot layout (not metadata/genes/reductions), so listing what
# can be cached doesn't pay the JSON-serialization cost of the full extract.

args <- commandArgs(trailingOnly = TRUE)
rds_path <- args[1]

s.obj <- readRDS(rds_path)

if (!is.null(s.obj[["RNA"]]) && inherits(s.obj[["RNA"]], "Assay5")) {
  tryCatch(s.obj <- JoinLayers(s.obj), error = function(e) NULL)
}

assays <- names(s.obj@assays)

get_assay_slots <- function(assay_name) {
  assay_obj <- s.obj[[assay_name]]
  # Seurat v5: layers are named (e.g. "counts", "data")
  layers <- tryCatch(names(assay_obj@layers), error = function(e) NULL)
  if (!is.null(layers) && length(layers) > 0)
    return(sort(unique(as.character(layers))))
  # Seurat v4: check standard slots for non-empty matrices
  Filter(function(s) {
    tryCatch(nrow(GetAssayData(s.obj, assay = assay_name, slot = s)) > 0,
             error = function(e) FALSE)
  }, c("counts", "data", "scale.data"))
}

assay_slots <- setNames(lapply(assays, function(a) I(get_assay_slots(a))), assays)

result <- list(
  n_cells     = ncol(s.obj),
  n_features  = nrow(s.obj),
  assays      = assays,
  assay_slots = assay_slots
)

cat(toJSON(result, auto_unbox = TRUE, null = "null"))
