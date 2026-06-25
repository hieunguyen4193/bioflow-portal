#!/bin/bash
#
# NUCLEOSOME_DISTANCE.sh
#
# Description:
#   Calculates nucleosome distance features for genomic fragments. This script processes
#   BED files containing fragment data and computes the distance from each fragment to
#   the nearest nucleosome reference position. It handles both gzip-compressed and
#   uncompressed input files.
#
# Usage:
#   ./NUCLEOSOME_DISTANCE.sh -i <inputfrag> -o <outputdir> -r <nucleosome_ref>
#
# Options:
#   -i <inputfrag>      Path to input BED file containing fragment coordinates
#                       (gzip-compressed or uncompressed). Required.
#   -o <outputdir>      Path to output directory where results will be written. Required.
#   -r <nucleosome_ref> Path to BED file containing nucleosome reference positions. Required.
#
# Output Files:
#   ${sample_id}.forward_Nucleosome.dist.sorted.bed   - Forward strand nucleosome distances
#   ${sample_id}.reverse_Nucleosome.dist.sorted.bed   - Reverse strand nucleosome distances
#   ${sample_id}.finished_Nucleosome.txt              - Completion marker (if uncommented)
#
# Dependencies:
#   - samtools (added to PATH)
#   - bedtools (bedtools closest)
#   - Standard Unix tools (cat, zcat, cut, awk, sort)
#
# Process:
#   1. Extracts sample ID from input filename
#   2. Separates fragments into forward and reverse strand coordinates
#   3. Sorts BED files by chromosome and position
#   4. Finds nearest nucleosome reference for each fragment using bedtools
#   5. Calculates distance as nucleosome_position - fragment_start
#   6. Cleans up intermediate files
#
# Notes:
#   - Only processes if completion marker does not exist
#   - Intermediate BED files are removed after processing
#   - Chromosome ordering uses natural sort (-k 1V,1)
# inputfrag="/Users/hieunguyen/outdir/ecd_wgs_and_enriched_features/ABC123.sorted_region_Full_fraglen_50_350.sorted.bed";
# outputdir="/Users/hieunguyen/outdir/ecd_wgs_and_enriched_features/test_FLEN_EM_ND_features";
# nucleosome_ref="/Users/hieunguyen/src/ecd_wgs_and_enriched_features/release/resources/nucleosome_maps/rpr_map_EXP0779.bed";
# export the samtools into path if not exists already.
# Author: Trong Hieu Nguyen
export PATH=/Users/hieunguyen/samtools/bin:$PATH;

while getopts "i:o:r:s:" opt; do
case ${opt} in
    i )
      inputfrag=$OPTARG
      ;;
    o )
      outputdir=$OPTARG
      ;;
    r )
      nucleosome_ref=$OPTARG
      ;;
    s )
      sample_id=$OPTARG
      ;;
      
    \? )
      echo "Usage: cmd [-i] inputbam [-o] outputdir [-n] nthreads"
      exit 1
      ;;
  esac
done

# ***** get the sample ID from the input bam file ***** #
# sample_id=$(echo ${inputfrag} | xargs -n 1 basename);
filename=$(echo ${inputfrag} | xargs -n 1 basename);
# sample_id=${sample_id%.bed*};

if [ ! -f "${outputdir}/${sample_id}.finished_Nucleosome.txt" ]; then
  echo -e "generating nucleosome features ..."

  if [[ "$filename" == *.gz ]]; then
    zcat ${inputfrag} | cut -f1,2,5,4 | \
      awk -v OFS='\t' '{$5=$2 + 1; print $1 "\t" $2 "\t" $5 "\t" $4 "\t" $3}' \
      > ${outputdir}/${sample_id}.forward_Nucleosome.bed
    zcat ${inputfrag} | cut -f1,3,5,4 | \
      awk -v OFS='\t' '{$5=$2 + 1; print $1 "\t" $2 "\t" $5 "\t" $4 "\t" $3}' \
      > ${outputdir}/${sample_id}.reverse_Nucleosome.bed
  else
    cat ${inputfrag} | cut -f1,2,5,4 | \
      awk -v OFS='\t' '{$5=$2 + 1; print $1 "\t" $2 "\t" $5 "\t" $4 "\t" $3}' \
      > ${outputdir}/${sample_id}.forward_Nucleosome.bed
    cat ${inputfrag} | cut -f1,3,5,4 | \
      awk -v OFS='\t' '{$5=$2 + 1; print $1 "\t" $2 "\t" $5 "\t" $4 "\t" $3}' \
      > ${outputdir}/${sample_id}.reverse_Nucleosome.bed
  fi


  # Sort your generated BED files
  sort -k 1V,1 -k 2n,2 ${outputdir}/${sample_id}.forward_Nucleosome.bed -o ${outputdir}/${sample_id}.sortedNuc.forward_Nucleosome.bed
  sort -k 1V,1 -k 2n,2 ${outputdir}/${sample_id}.reverse_Nucleosome.bed -o ${outputdir}/${sample_id}.sortedNuc.reverse_Nucleosome.bed

  ##### sort with -k 1V,1 to get the correct order of chromosome, add -t first to get first nucleosome only, match row numbers. 
  # option "-t first" or "-t last". default "-t all". First intersected or last intersected region, or all regions. 
  bedtools closest -a ${outputdir}/${sample_id}.sortedNuc.forward_Nucleosome.bed -b ${nucleosome_ref} -t first | awk -v OFS='\t' '{$10=$9 - $2;print $0}' > ${outputdir}/${sample_id}.forward_Nucleosome.dist.bed
  bedtools closest -a ${outputdir}/${sample_id}.sortedNuc.reverse_Nucleosome.bed -b ${nucleosome_ref} -t first | awk -v OFS='\t' '{$10=$9 - $2;print $0}' > ${outputdir}/${sample_id}.reverse_Nucleosome.dist.bed

  sort -k 1V,1 -k 2n,2 ${outputdir}/${sample_id}.forward_Nucleosome.dist.bed -o ${outputdir}/${sample_id}.forward_Nucleosome.dist.sorted.bed
  sort -k 1V,1 -k 2n,2 ${outputdir}/${sample_id}.reverse_Nucleosome.dist.bed -o ${outputdir}/${sample_id}.reverse_Nucleosome.dist.sorted.bed
  
  # touch ${outputdir}/${sample_id}.finished_Nucleosome.txt

  rm -rf ${outputdir}/${sample_id}*_Nucleosome.bed
  rm -rf ${outputdir}/${sample_id}*_Nucleosome.dist.bed
fi