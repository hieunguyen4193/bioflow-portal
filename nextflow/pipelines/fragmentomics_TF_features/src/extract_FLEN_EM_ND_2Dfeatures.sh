#!/bin/bash
# 
# Script: extract_FLEN_EM_ND_2Dfeatures.sh
# 
# Description:
#   Extracts Fragment Length (FLEN), End Motif (EM), and Nucleosome Distance (ND) 
#   2D features from a DNA fragment BED file. Combines these features with the 
#   original fragment data to generate a comprehensive feature matrix.
#
# Usage:
#   bash extract_FLEN_EM_ND_2Dfeatures.sh -i <inputbam> -o <outputdir> -r <nucleosome_ref> -f <path_to_fa>
#
# Required Arguments:
#   -i inputfrag          Path to input fragment BED file (or gzipped BED file)
#   -o outputdir          Output directory where results will be saved
#   -r nucleosome_ref     Path to nucleosome reference track file (BED format)
#   -f path_to_fa         Path to reference genome FASTA file (e.g., hg19.fa)
#
# Output Files:
#   - {sampleid}_FLEN_EM_ND.tsv       Main output file containing combined features
#   - finished_EM_FLEN_ND.txt         Completion marker file
#
# Workflow:
#   1. Validates command-line arguments
#   2. Extracts sample ID from input filename
#   3. Generates End Motif (EM) features using EM.sh
#   4. Generates Nucleosome Distance (ND) features using NUCLEOSOME_DISTANCE.sh
#   5. Processes intermediate results and extracts relevant columns
#   6. Combines all features with original fragment data using paste
#   7. Cleans up temporary intermediate files
#
# Dependencies:
#   - EM.sh script
#   - NUCLEOSOME_DISTANCE.sh script
#   - samtools (must be in PATH)
#   - Standard Unix utilities: cut, paste, cat, zcat, basename
#
# Notes:
#   - Handles both compressed (.gz) and uncompressed BED files
#   - Requires samtools binaries in /Users/hieunguyen/samtools/bin/
#   - Sample ID is derived from input filename by removing .bed extension
# export the samtools into path if not exists already.
export PATH=/Users/hieunguyen/samtools/bin:$PATH;

while getopts "i:o:r:f:" opt; do
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
    f )
      path_to_fa=$OPTARG
      ;;
    \? )
      echo "Usage: cmd [-i] inputbam [-o] outputdir [-r] nucleosome_ref [-f] path_to_fa"
      exit 1
      ;;
  esac
done

# use the converted input bed file to generate FLEN, EM, ND and the combined 2D features
# inputfrag="/Users/hieunguyen/outdir/ecd_wgs_and_enriched_features/ABC123.sorted_region_Full_fraglen_50_350.sorted.bed";

##### one can input different nucleosome track files here
# nucleosome_ref="/Users/hieunguyen/src/ecd_wgs_and_enriched_features/release/preprocessed_resources/refine_nucleosome_tracks/rpr_map_EXP0779.bed";

##### use the hg19 reference genome fasta file
# path_to_fa="/Users/hieunguyen/src/ecd_wgs_and_enriched_features/release/resources/hg19.fa";

##### save the output to a separate directory
# outputdir="/Users/hieunguyen/outdir/ecd_wgs_and_enriched_features/test_FLEN_EM_ND_features";

mkdir -p ${outputdir};

sampleid=$(echo ${inputfrag} | xargs -n 1 basename);
sampleid=${sampleid%.bed*};

# ***** generate EM features for each fragment ***** #
bash EM.sh -i ${inputfrag} -o ${outputdir} -f ${path_to_fa};

# ***** generate NUCLEOSOME DISTANCE features for each fragment ***** #
bash NUCLEOSOME_DISTANCE.sh -i ${inputfrag} -o ${outputdir} -r ${nucleosome_ref}

cat ${outputdir}/${sampleid}.forward_endmotif4bp.sorted.txt | cut -f4 > ${outputdir}/${sampleid}.forwardEM.txt
cat ${outputdir}/${sampleid}.reverse_endmotif4bp.sorted.txt | cut -f4 > ${outputdir}/${sampleid}.reverseEM.txt
cat ${outputdir}/${sampleid}.forward_Nucleosome.dist.sorted.bed | cut -f10 > ${outputdir}/${sampleid}.forwardNucleosome.txt
cat ${outputdir}/${sampleid}.reverse_Nucleosome.dist.sorted.bed | cut -f10 > ${outputdir}/${sampleid}.reverseNucleosome.txt

filename=$(echo ${inputfrag} | xargs -n 1 basename);
if [[ "$filename" == *.gz ]]; then
  paste <(zcat ${inputfrag}) \
    ${outputdir}/${sampleid}.forwardNucleosome.txt \
    ${outputdir}/${sampleid}.reverseNucleosome.txt \
    ${outputdir}/${sampleid}.forwardEM.txt \
    ${outputdir}/${sampleid}.reverseEM.txt > ${outputdir}/${sampleid}_FLEN_EM_ND.tsv
else 
  paste ${inputfrag} \
    ${outputdir}/${sampleid}.forwardNucleosome.txt \
    ${outputdir}/${sampleid}.reverseNucleosome.txt \
    ${outputdir}/${sampleid}.forwardEM.txt \
    ${outputdir}/${sampleid}.reverseEM.txt > ${outputdir}/${sampleid}_FLEN_EM_ND.tsv
fi

    
touch ${outputdir}/finished_EM_FLEN_ND.txt;

rm -rf ${outputdir}/${sampleid}.forwardEM.txt
rm -rf ${outputdir}/${sampleid}.reverseEM.txt
rm -rf ${outputdir}/${sampleid}.forwardNucleosome.txt
rm -rf ${outputdir}/${sampleid}.reverseNucleosome.txt
rm -rf ${outputdir}/${sampleid}*forward_endmotif4bp.sorted.txt
rm -rf ${outputdir}/${sampleid}*reverse_endmotif4bp.sorted.txt
rm -rf ${outputdir}/${sampleid}*forward_Nucleosome.dist.sorted.bed
rm -rf ${outputdir}/${sampleid}*reverse_Nucleosome.dist.sorted.bed

# EOF