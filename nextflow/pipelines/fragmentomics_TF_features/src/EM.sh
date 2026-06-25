#
# DESCRIPTION:
#   This script extracts and processes 4bp end motifs from fragment bed files.
#   It identifies the 4bp sequences at fragment ends (forward and reverse strands),
#   retrieves the actual DNA sequences from a reference genome, and outputs sorted
#   motif files with genomic coordinates.
#
# USAGE:
#   ./EM.sh -i <input_bed_file> -o <output_directory> -f <path_to_fasta>
#
# OPTIONS:
#   -i  Path to input fragment BED file (can be gzipped)
#   -o  Output directory where results will be written
#   -f  Path to reference FASTA file (e.g., hg19.fa)
#
# INPUTS:
#   - Input BED file: Tab-delimited format with columns:
#     chromosome, start, end, read_ID, score, strand
#   - Reference FASTA file with indexed sequences
#
# OUTPUTS:
#   - ${sample_id}.forward_endmotif4bp.sorted.txt
#     Tab-delimited: chromosome, start, end, 4bp_sequence, read_ID (forward strand)
#   - ${sample_id}.reverse_endmotif4bp.sorted.txt
#     Tab-delimited: chromosome, start, end, 4bp_sequence, read_ID (reverse strand)
#
# DEPENDENCIES:
#   - bedtools (getfasta command)
#   - samtools (exported to PATH)
#   - awk, sort, cat/zcat
#
# NOTES:
#   - Coordinates are 0-based (compatible with FASTA indexing)
#   - Forward strand: extracts 4bp starting at fragment start
#   - Reverse strand: extracts 4bp ending at fragment end
#   - Creates output directory if it doesn't exist
#   - Intermediate BED files are cleaned up after processing
#   - Skips processing if .finished_4bpEM.txt marker file exists

# inputfrag="/Users/hieunguyen/outdir/ecd_wgs_and_enriched_features/ABC123.sorted_region_Full_fraglen_50_350.bed";
# path_to_fa="/Users/hieunguyen/src/ecd_wgs_and_enriched_features/release/resources/hg19.fa";
# outputdir="/Users/hieunguyen/outdir/ecd_wgs_and_enriched_features/test_FLEN_EM_ND_features";

# export the samtools into path if not exists already.
export PATH=/Users/hieunguyen/samtools/bin:$PATH;

while getopts "i:o:f:s:" opt; do
case ${opt} in
    i )
      inputfrag=$OPTARG
      ;;
    o )
      outputdir=$OPTARG
      ;;
    f )
      path_to_fa=$OPTARG
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

echo -e "working on sample " $sample_id

mkdir -p ${outputdir};

if [ ! -f "${outputdir}/${sample_id}.finished_4bpEM.txt" ]; then
    echo -e "getting 4bp end motif"
    # ***** coordinates are already in 0-based, the same based as coordinates in fasta file ***** #
    if [[ "$filename" == *.gz ]]; then
        zcat ${inputfrag} | \
          awk '{start=$2; end= $2 + 4; name= $4; strand = "+"; if (start > 0){print $1 "\t" start "\t" end "\t" name "\t" "1" "\t" strand} }' \
        > ${outputdir}/${sample_id}.forward_endcoord4bp.bed;
        zcat ${inputfrag} | \
          awk '{start=$3 - 4; end= $3; name= $4; strand = "-"; if (start > 0) {print $1 "\t" start "\t" end "\t" name "\t" "1" "\t" strand} }' \
        > ${outputdir}/${sample_id}.reverse_endcoord4bp.bed;
    else
        cat ${inputfrag} | \
          awk '{start=$2; end= $2 + 4; name= $4; strand = "+"; if (start > 0){print $1 "\t" start "\t" end "\t" name "\t" "1" "\t" strand} }' \
        > ${outputdir}/${sample_id}.forward_endcoord4bp.bed;
        cat ${inputfrag} | \
          awk '{start=$3 - 4; end= $3; name= $4; strand = "-"; if (start > 0) {print $1 "\t" start "\t" end "\t" name "\t" "1" "\t" strand} }' \
        > ${outputdir}/${sample_id}.reverse_endcoord4bp.bed;
    fi

    # ***** get the end motif and the read ID ***** #
    # bedtools getfasta -s -name -tab -fi ${path_to_fa} -bed ${outputdir}/${sample_id}.forward_endcoord4bp.bed | \
    #   awk -v OFS='\t' '{split($0, a, "::"); $1=a[1]; print $0}'  > ${outputdir}/${sample_id}.forward_endmotif4bp.txt
    # bedtools getfasta -s -name -tab -fi ${path_to_fa} -bed ${outputdir}/${sample_id}.reverse_endcoord4bp.bed | \
    # awk -v OFS='\t' '{split($0, a, "::"); $1=a[1]; print $0}'  > ${outputdir}/${sample_id}.reverse_endmotif4bp.txt
    # ***** sort the output file by readID ***** #
    # sort -k1,1 ${outputdir}/${sample_id}.forward_endmotif4bp.txt > ${outputdir}/${sample_id}.forward_endmotif4bp.sorted.txt
    # sort -k1,1 ${outputdir}/${sample_id}.reverse_endmotif4bp.txt > ${outputdir}/${sample_id}.reverse_endmotif4bp.sorted.txt
    
    # ***** for this getfasta, we get the chromosome, start and end coordinate of the reads, not just the read ID as the above script. ***** #
    bedtools getfasta -s -name -tab -fi ${path_to_fa} -bed ${outputdir}/${sample_id}.forward_endcoord4bp.bed | \
        awk -v OFS='\t' '{split($1, a, "::"); split(a[2], b, /[:\-()+]+/); print b[1], b[2], b[3], $2, a[1]}'  > ${outputdir}/${sample_id}.forward_endmotif4bp.txt
    bedtools getfasta -s -name -tab -fi ${path_to_fa} -bed ${outputdir}/${sample_id}.reverse_endcoord4bp.bed | \
        awk -v OFS='\t' '{split($1, a, "::"); split(a[2], b, /[:\-()+]+/); print b[1], b[2], b[3], $2, a[1]}'  > ${outputdir}/${sample_id}.reverse_endmotif4bp.txt
    # ***** then we sort the output file by chromosome and coordinate ***** #
    sort -k 1V,1 -k 2n,2 ${outputdir}/${sample_id}.forward_endmotif4bp.txt > ${outputdir}/${sample_id}.forward_endmotif4bp.sorted.txt
    sort -k 1V,1 -k 2n,2 ${outputdir}/${sample_id}.reverse_endmotif4bp.txt > ${outputdir}/${sample_id}.reverse_endmotif4bp.sorted.txt
    # touch ${outputdir}/${sample_id}.finished_4bpEM.txt

    # ***** clean up ***** #
    rm -rf ${outputdir}/${sample_id}.forward_endcoord4bp.bed
    rm -rf ${outputdir}/${sample_id}.reverse_endcoord4bp.bed
    rm -rf ${outputdir}/${sample_id}.forward_endmotif4bp.txt
    rm -rf ${outputdir}/${sample_id}.reverse_endmotif4bp.txt
fi