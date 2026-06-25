#!/bin/bash
#
# SCRIPT: preprocess_BAM_files.sh
# DESCRIPTION:
#   Preprocesses BAM files for fragmentomics analysis. Performs sorting, indexing,
#   optional duplicate marking, fragment length extraction, BAM splitting by insert size,
#   genome coverage estimation, and conversion to BEDPE format.
#
# USAGE:
#   bash preprocess_BAM_files.sh -i <inputbam> -o <outputdir> -n <nthreads> \
#     -q <short_lower> -w <short_upper> -e <long_lower> -r <long_upper> \
#     -c <checkdir> -m <markdup> -t <targeted_region>
#
# OPTIONS:
#   -i INPUT_BAM      Path to input BAM file (required)
#   -o OUTPUT_DIR     Output directory for processed files (required)
#   -n NTHREADS       Number of threads for parallel processing (default: 1)
#   -q SHORT_LOWER    Lower bound for short fragment length cutoff
#   -w SHORT_UPPER    Upper bound for short fragment length cutoff
#   -e LONG_LOWER     Lower bound for long fragment length cutoff
#   -r LONG_UPPER     Upper bound for long fragment length cutoff
#   -c CHECK_DIR      Directory for checkpoint/output files
#   -m MARKDUP        Enable duplicate marking (true/false) (default: false)
#   -t TARGETED_REGION Targeted genomic region for analysis
#
# WORKFLOW:
#   1. Sort and index input BAM file
#   2. Optionally mark duplicates using Picard
#   3. Extract total read count
#   4. Split BAM by chromosome
#   5. Extract fragment lengths per chromosome
#   6. Split BAM into short and long fragments based on insert size thresholds
#   7. Estimate genome-wide coverage using bedtools
#   8. Convert BAM to BEDPE format with fragment filtering
#
# DEPENDENCIES:
#   - samtools (v1.x or higher)
#   - bedtools
#   - picard.jar (if -m true is specified)
#   - Python 3 with custom scripts: bam2bed.py, parse_genomeCov_from_bedtools.py
#
# OUTPUT FILES:
#   - {sampleid}.sorted.bam                 Sorted and indexed BAM file
#   - {sampleid}.sorted.markdup.bam         Duplicate-marked BAM (if enabled)
#   - {sampleid}.total_reads.txt            Total read count
#   - {sampleid}_splitChroms/               Directory with per-chromosome BAM files
#   - {sampleid}_{short_lower}_{short_upper}.short.bam   Short fragment BAM
#   - {sampleid}_{long_lower}_{long_upper}.long.bam      Long fragment BAM
#   - {sampleid}.genomeCov.txt              Genome coverage statistics
#   - BEDPE formatted files with fragment filtering
#
# AUTHOR: Trong Hieu Nguyen
# DATE: 29.01.2026
#
# export the samtools into path if not exists already.
# export PATH=/Users/hieunguyen/samtools/bin:$PATH;

while getopts "i:o:n:q:w:e:r:c:m:t:s:p:b:" opt; do
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
    q )
      short_lower=$OPTARG
      ;;
    w )
      short_upper=$OPTARG
      ;;
    e )
      long_lower=$OPTARG
      ;;
    r )
      long_upper=$OPTARG
      ;;
    c )
      checkdir=$OPTARG
      ;;
    m )
      markdup=$OPTARG
      ;;
    t )
      targeted_region=$OPTARG
      ;;
    s )
      sampleid=$OPTARG
      ;;
    p )
      parse_genomeCov_from_bedtools=$OPTARG
      ;;
    b )
      bam2bed=$OPTARG
      ;;
    
    
    
    \? )
      echo "Usage: cmd [-i] inputbam [-o] outputdir [-n] nthreads"
      exit 1
      ;;
  esac
done

# example command line arguments
# inputbam="/Users/hieunguyen/storage/WGS_bam/input.bam";
# outputdir="/Users/hieunguyen/storage/WGS_bam/outputdir"
# nthreads=12;

mkdir -p ${outputdir};
mkdir -p ${checkdir};

# ***** get the sample ID from the input bam file ***** #
if [ "${sampleid}" == "none" ]; then
  sampleid=$(echo ${inputbam} | xargs -n 1 basename);
  sampleid=${sampleid%.bam*};
fi
if [ ! -f "${outputdir}/${sampleid}.preprocessed.bam" ]; then
  echo -e "sorting and indexing the input bam file " $sampleid;

  samtools view -h -f 3 ${inputbam} | \
      samtools sort -@ ${nthreads} \
      -o ${outputdir}/${sampleid}.preprocessed.bam;
  samtools index ${outputdir}/${sampleid}.preprocessed.bam;

  echo -e "finished sorting and indexing for " $sampleid;
  inputbam=${outputdir}/${sampleid}.preprocessed.bam;
else
  echo -e "sorted and indexed bam file already exists for " $sampleid;
  inputbam=${outputdir}/${sampleid}.preprocessed.bam;
fi

if [ "${markdup}" == "true" ]; then
    echo "Mark duplicates using picard ..."
    # download picard from https://github.com/broadinstitute/picard/releases/download/3.4.0/picard.jar
    java -Xms512m -Xmx4g -jar ./picard.jar MarkDuplicates \
            -I ${inputbam} \
            -O ${outputdir}/${sampleid}.sorted.markdup.bam \
            -M ${outputdir}/${sampleid}.marked_dup_metrics.txt
    samtools index ${outputdir}/${sampleid}.sorted.markdup.bam;

    echo -e "using the markdup bam as input for downstream tasks ..."
    inputbam=${outputdir}/${sampleid}.sorted.markdup.bam;
else
    echo -e "Using the sorted and indexed bam file: " $inputbam;
fi

echo -e "###########################################################"
echo -e "Using the input bam file " $inputbam;
echo -e "###########################################################"

# ***** get the sample id again, added .sorted because we use the sorted bam file ***** #
sampleid=$(echo ${inputbam} | xargs -n 1 basename);
sampleid=${sampleid%.bam*};

# ***** calculate total number of reads in the input bam file ***** #
if [ ! -f "${outputdir}/${sampleid}.total_reads.txt" ]; then
    samtools view -c ${inputbam} > ${outputdir}/${sampleid}.total_reads.txt
fi

# ***** split bam file to each chromosome and extract fragment lengths ***** #
mkdir -p ${outputdir}/${sampleid}_splitChroms;

for i in {1..22}; do \
    if [ ! -f "${outputdir}/${sampleid}_splitChroms/chr${i}.flen.txt" ]; then
        samtools view -b ${inputbam} chr${i} > ${outputdir}/${sampleid}_splitChroms/chr${i}.bam;
        samtools view ${outputdir}/${sampleid}_splitChroms/chr${i}.bam | cut -f9 > ${outputdir}/${sampleid}_splitChroms/chr${i}.flen.txt;
        rm -rf ${outputdir}/${sampleid}_splitChroms/chr${i}.bam; # clean up the chromosome bam to save space. 
    else
        echo -e "output BAM file exists";
    fi
done

# ***** split BAM file to short and long based on fragment length, input args ***** #
if [ ! -f "${outputdir}/${sampleid}_${long_lower}_${long_upper}.long.bam" ]; then
  echo -e "splitting BAM file into short and long BAM files ..."
  samtools view -h ${inputbam} | \
      awk 'substr($0,1,1)=="@" || ($9 >= '${short_lower}' && $9 <= '${short_upper}') || ($9 <= -'${short_lower}' && $9 >= -'${short_upper}')' | \
      samtools view -b | samtools sort -@ ${nthreads} > ${outputdir}/${sampleid}_${short_lower}_${short_upper}.short.bam;

  # ***** split BAM file: long_lower <= insert size <= long_upper ***** #
  samtools view -h ${inputbam} | \
      awk 'substr($0,1,1)=="@" || ($9 >= '${long_lower}' && $9 <= '${long_upper}') || ($9 <= -'${long_lower}' && $9 >= -'${long_upper}')' | \
      samtools view -b | samtools sort -@ ${nthreads} > ${outputdir}/${sampleid}_${long_lower}_${long_upper}.long.bam;

  samtools index ${outputdir}/${sampleid}_${short_lower}_${short_upper}.short.bam;
  samtools index ${outputdir}/${sampleid}_${long_lower}_${long_upper}.long.bam;
fi

# ***** estimate genome coverage ***** #
echo -e "estimate average genome coverage for the input bam file " $sampleid;

if [ ! -f "${outputdir}/${sampleid}.genomeCov.txt" ]; then
    bedtools genomecov -ibam ${inputbam} -g ${chrom_size_file} > ${outputdir}/${sampleid}.genomeCov.txt
    echo -e "parse genome coverage file to get average coverage " $sampleid;
    # python parse_genomeCov_from_bedtools.py \
    python ${parse_genomeCov_from_bedtools} \
        --input ${outputdir}/${sampleid}.genomeCov.txt \
        --output ${outputdir};
else
    echo "genome coverage file already exists: ${outputdir}/${sampleid}.genomeCov.txt"
fi
echo -e "done for genome coverage estimation for " $sampleid;
  
# ***** estimate genome coverage for each chromosome ***** #
# echo -e "estimate average genome coverage for each chromosome for the input bam file " $sampleid;

# for chri in {1..22}; do \
#   if [ ! -f "${outputdir}/${sampleid}.chr${chri}.txt" ]; then
#       bedtools genomecov -ibam ${inputbam} -g ${chrom_size_file} > ${outputdir}/${sampleid}.chr${chri}.txt
#       echo -e "parse genome coverage file to get average coverage " $sampleid;
#       python parse_genomeCov_from_bedtools.py \
#           --input ${outputdir}/${sampleid}.chr${chri}.txt \
#           --output ${outputdir};
#   else
#       echo "genome coverage file already exists: ${outputdir}/${sampleid}.chr${chri}.txt"
#   fi
# done

# echo -e "done for genome coverage estimation for " $sampleid;

##### >>>>> Note on 29.01.2026: here we benchmark 2 tools for converting BAM to BEDPE:
##### 1) bedtools bamtobed -bedpe -cigar -i input.bam > output.bedpe
##### 2) the custom python script
##### we temporarily go with the python version, it would be easier to integrate 
##### with the downstream analysis scripts.

# ***** convert BAM to BEDPE format ***** #
# echo -e "converting BAM to BEDPE format for " $sampleid;
# bedtools bamtobed -bedpe -cigar -i ${inputbam} > ${outputdir}/${sampleid}.bedpe;
# echo -e "done for converting BAM to BEDPE format for " $sampleid;

# python bam2bed.py \
python ${bam2bed} \
    --inputbam ${inputbam} \
    --region ${targeted_region} \
    --outputdir ${outputdir} \
    --min_frag_length 50 \
    --max_frag_length 350 \
    --gzipbed True \
    --mapq 30 --sampleid ${sampleid}
    
# example commands
# bash preprocess_BAM_files.sh \
# -i /Users/hieunguyen/storage/WGS_bam/input.bam \
# -o /Users/hieunguyen/storage/WGS_bam/outputdir \
# -n 12;