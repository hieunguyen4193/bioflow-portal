#' Calculate Copy Number Alterations (CNA) from BAM Files
#'
#' This script performs copy number alteration analysis on whole genome sequencing
#' BAM files using the QDNAseq package. It bins the genome, calculates read counts,
#' applies quality filters, corrects for systematic biases, normalizes, segments,
#' and calls copy number states.
#'
#' @section Input Arguments:
#' \describe{
#'   \item{-i, --input}{Path to input BAM file (required)}
#'   \item{-b, --bin}{Path to QDNAseq bin file in RDS format (required)}
#'   \item{-o, --output}{Output directory path for results (required)}
#' }
#'
#' @section Output:
#' BED format file containing copy number segments with the following columns:
#' \describe{
#'   \item{chrom}{Chromosome identifier (e.g., chr1)}
#'   \item{start}{Start position of bin}
#'   \item{end}{End position of bin}
#'   \item{log2.ratio}{Log2 ratio of copy number relative to baseline}
#' }
#'
#' @section Functions:
#' \describe{
#'   \item{calculate_CNA()}{Orchestrates the complete CNA pipeline including
#'   read counting, filtering, correction, normalization, smoothing, segmentation,
#'   and calling}
#'   \item{format_cna_output()}{Converts QDNAseq output object to BED format}
#' }
#'
#' @examples
#' \dontrun{
#' inputbam="/path/to/sample.sorted.bam"
#' binfile="/path/to/bin1M.rds"
#' outputdir="/path/to/output"
#' Rscript calculate_CNA.R --input ${inputbam} --bin ${binfile} --output ${outputdir}
#' }
#'
#' @import QDNAseq Biobase dplyr tidyverse GenomicRanges BSgenome.Hsapiens.UCSC.hg19
#' @import hash Rsamtools parallel argparse testit comprehenr
#'
#' @author Script for computing CNA from WGS data
#' Trong Hieu Nguyen

gc()
rm(list = ls())

library(QDNAseq)
library(Biobase)
library(dplyr)
library(tidyverse)
library(GenomicRanges)
library(BSgenome.Hsapiens.UCSC.hg19)
library(hash)
library(Rsamtools)
library(parallel)
library(GenomicRanges)
library(argparse)
library(testit)
library(comprehenr)


# ***** input args ***** #

# ***** EXAMPLE input args ***** #
# resource.dir <- "/home/hieunguyen/src/ecd_wgs_and_enriched_features/resources/QDNAseq"
# outputdir <- "/home/hieunguyen/src/ecd_wgs_and_enriched_features/tmp_output"
# bamfile <- "/home/hieunguyen/storage/WGS_bam/input.sorted.bam"
# 
parser <- ArgumentParser()
parser$add_argument("-i", "--input", action="store",
                    help="path to input bam fiel")
parser$add_argument("-b", "--bin", action="store",
                    help="path to input bam fiel")
parser$add_argument("-o", "--output", action="store",
                    help="Path to save  output")
parser$add_argument("-s", "--sampleid", action="store",
                    help="Path to save  output")

args <- parser$parse_args()

bamfile <- args$input
outputdir <- args$output
path.to.bin.file <- args$bin
sampleid <- args$sampleid

bin.name <- str_replace_all(basename(path.to.bin.file), ".rds", "")

message(sprintf("Input bam file %s", bamfile))
message(sprintf("output will be saved to %s", outputdir))
message(sprintf("Using the CNA bin file %s, name %s", path.to.bin.file, bin.name))

binfile <- readRDS(path.to.bin.file)

# bin1M <- readRDS(file.path(resource.dir, "bin1M.rds"))
# bin100kb <- readRDS(file.path(resource.dir, "bin100kb.rds"))
if (sampleid != "none"){
  filename <- sampleid
} else {
  filename <- str_replace(basename(bamfile), ".bam", "")
}

print(sprintf("Working on bam file %s", filename))

dir.create(outputdir, showWarnings = FALSE, recursive = TRUE)

# ***** helper functions ***** #
calculate_CNA <- function(bin, bamfile){
  readCounts <- binReadCounts(bins = bin, bamfiles = bamfile)
  
  readCountsFiltered <- applyFilters(readCounts, residual=TRUE, blacklist=TRUE)
  readCountsFiltered <- estimateCorrection(readCountsFiltered)
  copyNumbers <- correctBins(readCountsFiltered)
  copyNumbersNormalized <- normalizeBins(copyNumbers)
  copyNumbersSmooth <- smoothOutlierBins(copyNumbersNormalized)
  
  copyNumbersSegmented <- segmentBins(copyNumbersSmooth, transformFun="log2")
  copyNumbersSegmented <- normalizeSegmentedBins(copyNumbersSegmented)
  
  copyNumbersCalled <- callBins(copyNumbersSegmented)
  function.output <- list(CNA = copyNumbersCalled, readCounts = readCountsFiltered)
  return(function.output)  
}

format_cna_output <- function(cna.obj){
  # ***** save copy number data frame
  # and format the dataframe as <chr>TAB<start>TAB<end>TAB<Log2-ratio>
  cnadf <- data.frame(cna.obj$CNA@assayData$copynumber) %>%
    rownames_to_column("bin.name")
  colnames(cnadf) <- c("bin.name", "log2.ratio")
  cnadf <- cnadf %>% rowwise() %>%
    mutate(chrom = sprintf("chr%s", str_split(bin.name, ":")[[1]][[1]])) %>%
    mutate(start = str_split(str_split(bin.name, ":")[[1]][[2]], "-")[[1]][[1]] ) %>%
    mutate(end = str_split(str_split(bin.name, ":")[[1]][[2]], "-")[[1]][[2]] )
  
  cnadf <- cnadf[, c("chrom", "start", "end", "log2.ratio")]
  return(cnadf)
}

# ***** END of helper functions ***** #

cna.bin <- calculate_CNA(bin = binfile, bamfile = bamfile)
output.cnadf <- format_cna_output(cna.bin)

write.table(output.cnadf, 
            file.path(outputdir, sprintf("%s.%s.bed", filename, bin.name)), 
            sep = "\t", 
            row.names = FALSE, 
            col.names = FALSE)

# example cmd
# inputbam="/home/hieunguyen/outdir/ecd_wgs_and_enriched_features/ABC123_sampling15.sorted.bam";
# cna_resource_dir="/home/hieunguyen/src/ecd_wgs_and_enriched_features/release/resources/QDNAseq";
# outputdir="/home/hieunguyen/outdir/ecd_wgs_and_enriched_features";
# binfile=${cna_resource_dir}/bin1M.rds;
# Rscript calculate_CNA.R --input ${inputbam} --output ${outputdir}/CNA --bin ${binfile};
# binfile=${cna_resource_dir}/bin100kb.rds;
# Rscript calculate_CNA.R --input ${inputbam} --output ${outputdir}/CNA --bin ${binfile};
# EOF