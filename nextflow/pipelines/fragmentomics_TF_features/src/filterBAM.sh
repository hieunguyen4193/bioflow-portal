#!/bin/bash
#
# DESCRIPTION:
#   Filters BAM files based on fragment size range and/or genomic regions defined in a BED file.
#   Supports filtering by insert size (TLEN field) and by genomic coordinates.
#
# USAGE:
#   bash filterBAM.sh -i <inputbam> -o <outputdir> -n <nthreads> [-l <lower_bound>] [-u <upper_bound>] [-b <bedfile>]
#
# OPTIONS:
#   -i    Input BAM file path (required)
#   -o    Output directory for filtered BAM files (required)
#   -n    Number of threads for samtools sort (required)
#   -l    Lower bound for fragment size filtering (optional)
#   -u    Upper bound for fragment size filtering (optional)
#   -b    BED file for genomic region filtering (optional)
#
# EXAMPLES:
#   # Filter by fragment size (200-500 bp)
#   bash filterBAM.sh -i input.bam -o ./output -n 4 -l 200 -u 500
#
#   # Filter by BED file regions
#   bash filterBAM.sh -i input.bam -o ./output -n 4 -b regions.bed
#
#   # Filter by both fragment size and BED regions
#   bash filterBAM.sh -i input.bam -o ./output -n 4 -l 200 -u 500 -b regions.bed
#
# DEPENDENCIES:
#   - samtools (must be available in PATH or at /Users/hieunguyen/samtools/bin/)
#   - awk
#
# OUTPUT:
#   - Filtered BAM files named as: {sampleid}_{lower_bound}_{upper_bound}.filtered.bam
#   - Filtered BAM files named as: {sampleid}_{bedname}.filtered.bam
#   - Corresponding BAM index files (.bai)
#
# NOTES:
#   - Fragment size filtering includes both positive and negative insert sizes
#   - Output files are sorted and indexed for downstream analysis
# export the samtools into path if not exists already.
export PATH=/Users/hieunguyen/samtools/bin:$PATH;

while getopts "i:o:n:l:u:b:s:" opt; do
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
    l )
      lower_bound=$OPTARG
      ;;
    u )
      upper_bound=$OPTARG
      ;;
    b )
      bedfile=$OPTARG
      ;;
    s )
      sampleid=$OPTARG
      ;;
       
    \? )
      echo "Usage: cmd [-i] inputbam [-o] outputdir [-n] nthreads"
      exit 1
      ;;
  esac
done

# sampleid=$(echo ${inputbam} | xargs -n 1 basename);
# sampleid=${sampleid%.bam*};

# samtools view -h ${inputbam} | \
#       awk 'substr($0,1,1)=="@" || ($9 >= '${lower_bound}' && $9 <= '${upper_bound}') || ($9 <= -'${lower_bound}' && $9 >= -'${upper_bound}')' | \
#       samtools view -b | samtools sort -@ ${nthreads} > ${outputdir}/${sampleid}_${lower_bound}_${upper_bound}.filtered.bam;
# samtools index ${outputdir}/${sampleid}_${lower_bound}_${upper_bound}.filtered.bam;

# samtools view -b ${inputbam} -L ${bedfile} > ${outputdir}/${sapleid}_${bedname}.filtered.bam;
# samtools index ${outputdir}/${sapleid}_${bedname}.filtered.bam;

if [[ -n "$lower_bound" && -n "$upper_bound" ]]; then
    echo "Running fragment size filter: ${lower_bound} to ${upper_bound}..."
    
    samtools view -h "${inputbam}" | \
    awk -v lb="$lower_bound" -v ub="$upper_bound" \
    'substr($0,1,1)=="@" || ($9 >= lb && $9 <= ub) || ($9 <= -lb && $9 >= -ub)' | \
    samtools view -b | samtools sort -@ "${nthreads:-1}" > "${outputdir}/${sampleid}_${lower_bound}_${upper_bound}.filtered.bam"
    
    samtools index "${outputdir}/${sampleid}_${lower_bound}_${upper_bound}.filtered.bam"
fi

if [[ -n "$bedfile" ]]; then
    echo "Running BED file filter: ${bedfile}..."
    bedname=$(basename "${bedfile}" .bed)
    
    samtools view -b "${inputbam}" -L "${bedfile}" > "${outputdir}/${sampleid}_${bedname}.filtered.bam"
    samtools index "${outputdir}/${sampleid}_${bedname}.filtered.bam"
fi

# ***** EOF ***** #