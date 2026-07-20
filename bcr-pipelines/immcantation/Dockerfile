# Immcantation BCR repertoire pipeline image.
# Base image already bundles: IgBLAST + IMGT germline/igblast reference databases
# (human, mouse, rhesus_monkey) under /usr/local/share/{igblast,germlines}, plus
# the presto/changeo Python CLIs and the R packages alakazam/shazam/tigger/scoper/
# dowser/airr used by this pipeline's analysis steps.
FROM immcantation/suite:4.5.0

# Report rendering + plotting extras not guaranteed to be present in the base image.
RUN Rscript -e '\
pkgs <- c("rmarkdown", "knitr", "DT", "dplyr", "ggplot2", "optparse"); \
missing <- pkgs[!sapply(pkgs, requireNamespace, quietly = TRUE)]; \
if (length(missing) > 0) install.packages(missing, repos = "https://cloud.r-project.org")'
