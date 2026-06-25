#!/bin/bash
# Script: QC_Coverage.sh
# Description: Computes coverage statistics for BAM files across specified genomic regions (BED file)
#              using bedtools multicov. Supports parallel processing of multiple BAM and BED file combinations.
#
# Usage: bash QC_Coverage.sh -i <inputbam> -o <outputdir> -n <nthreads> -b <bedfile>
#
# Options:
#   -i  inputbam    Required. Path to the input BAM file (sorted and indexed)
#   -o  outputdir   Required. Output directory where results will be written
#   -n  nthreads    Required. Number of threads to use for processing
#   -b  bedfile     Required. BED file containing genomic regions for coverage calculation
#
# Output:
#   Generates a coverage file at: ${outputdir}/${bedname}/${sampleid}_${bedname}_coverage.txt
#   containing per-region coverage counts for each sample
#
# Dependencies:
#   - bedtools (multicov command)
#   - basename
#   - parallel (for batch processing mode)
#
# Notes:
#   - Sample ID is extracted from BAM filename (removes .bam extension and path)
#   - BED name is extracted from BED filename (removes .bed extension and path)
#   - Output directory structure is created as: ${outputdir}/${bedname}/
#   - For parallel batch processing: use nested loop with parallel -j flag to distribute jobs
#
# Example:
#   bash QC_Coverage.sh \
#     -i sample.sorted.bam \
#     -o /output/coverage \
#     -n 12 \
#     -b regions.bed
# Author: Trong Hieu Nguyen
while getopts "i:o:n:b:" opt; do
case ${opt} in
    i )
      inputbam=$OPTARG
      ;;
    o )
      outputdir=$OPTARG
      ;;
    n )
      nthreads=$OPTARG
      ;;
    b )
      bedfile=$OPTARG
      ;;
       
    \? )
      echo "Usage: cmd [-i] inputbam [-o] outputdir [-n] nthreads"
      exit 1
      ;;
  esac
done

sampleid=$(echo ${inputbam} | xargs -n 1 basename);
sampleid=${sampleid%.bam*};

bedname=$(echo ${bedfile} | xargs -n 1 basename);
bedname=${bedname%.bed*};

mkdir -p  ${outputdir}/${bedname};
bedtools multicov -bams ${inputbam} -bed ${bedfile} > ${outputdir}/${bedname}/${sampleid}_${bedname}_coverage.txt
# example input
# inputbam="/mnt/DATASM14/DATA_HIEUNGUYEN/outdir_2026/exp7_filterBAM/9-ZLBE003NB_S95075-S97075.sorted.sorted/9-ZLBE003NB_S95075-S97075.sorted.sorted_50_150.filtered.bam"
# bedfile="/home/hieunguyen/src_2026/ecd_wgs_and_enriched_features/release/preprocessed_resources/TFBS/p73.Top1000sites_1250.hg19.bed"
# nthreads=12
# outputdir="/mnt/DATASM14/DATA_HIEUNGUYEN/outdir_2026/QC_coverage"
# bash QC_Coverage.sh -i ${inputbam} -o ${outputdir} -n ${nthreads} -b ${bedfile}

# ***** run in parallel *****
files=$(ls /mnt/NAS_PROJECT/vol_ECDteam/DATA_HIEUNGUYEN/outdir/exp1_lowDepth/*/*.sorted.bam);
allbeds=$(ls ./preprocessed_resources/TFBS/*.bed);
outputdir="/mnt/DATASM14/DATA_HIEUNGUYEN/outdir_2026/QC_coverage"
nthreads=12;
for inputbam in $files;do parallel -j 100 bash QC_Coverage.sh -i ${inputbam} -o ${outputdir} -n ${nthreads} -b ${} ::: ${allbeds};done
