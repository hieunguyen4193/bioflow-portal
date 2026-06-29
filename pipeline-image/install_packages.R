#!/usr/bin/env Rscript
# Baked into the pipeline Docker image — runs once at build time.

already <- function(pkg) requireNamespace(pkg, quietly = TRUE)

install_cran <- function(...) {
  pkgs <- c(...)
  missing <- pkgs[!sapply(pkgs, already)]
  if (length(missing) == 0) { message("CRAN packages already present: ", paste(pkgs, collapse = ", ")); return(invisible()) }
  message("Installing from CRAN: ", paste(missing, collapse = ", "))
  install.packages(missing, repos = "https://cloud.r-project.org", quiet = FALSE)
}

install_bioc <- function(...) {
  pkgs <- c(...)
  missing <- pkgs[!sapply(pkgs, already)]
  if (length(missing) == 0) { message("Bioc packages already present: ", paste(pkgs, collapse = ", ")); return(invisible()) }
  message("Installing from Bioconductor: ", paste(missing, collapse = ", "))
  if (!already("BiocManager")) install.packages("BiocManager", repos = "https://cloud.r-project.org")
  BiocManager::install(missing, ask = FALSE, update = FALSE)
}

# ── CRAN ─────────────────────────────────────────────────────────────────────
install_cran(
  "dplyr", "jsonlite", "rmarkdown", "ggplot2", "patchwork",
  "stringr", "tibble", "DT", "hash", "msigdbr"
)

# ── Bioconductor ─────────────────────────────────────────────────────────────
install_bioc(
  "clusterProfiler", "org.Hs.eg.db", "org.Mm.eg.db",
  "BiocNeighbors", "ComplexHeatmap", "BiocParallel"
)

# ── GitHub: CellChat ─────────────────────────────────────────────────────────
if (!already("CellChat")) {
  message("Installing CellChat from GitHub...")
  if (!already("devtools")) install_cran("devtools")
  devtools::install_github("jinworks/CellChat", upgrade = "never")
} else {
  message("CellChat already present: ", as.character(packageVersion("CellChat")))
}

message("\nInstalled package versions:")
pkgs <- c("CellChat", "clusterProfiler", "org.Hs.eg.db", "org.Mm.eg.db",
          "msigdbr", "dplyr", "ggplot2", "rmarkdown")
for (p in pkgs) {
  v <- tryCatch(as.character(packageVersion(p)), error = function(e) "MISSING")
  message(sprintf("  %-25s %s", p, v))
}
