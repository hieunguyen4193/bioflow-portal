# inputfrag=$1;
# bound=$2;
# outputdir=$3;

# **** example input args *****
# inputfrag="/media/hieunguyen/HNSD01/outdir/FragmentomicsFeatures/nextflow_output/OUTPUT/exp7_FLEN_EM_ND_2Dfeatures/9-ZMC025NB_S95001-S97001_FLEN_EM_ND.tsv";
# bound=50
# outputdir="."
# sampleid="9-ZMC025NB_S95001-S97001"

while getopts "i:b:o:c:s:" opt; do
case ${opt} in
    i )
      inputfrag=$OPTARG
      ;;
    b )
      inputbam=$OPTARG
      ;;
    o )
      outputdir=$OPTARG
      ;;
    c )
      bound=$OPTARG
      ;;
    s )
      sampleid=$OPTARG
      ;;
    \? )
      echo "Usage: cmd [-i] inputfrag [-b] inputbam [-o] outputdir [-c] bound [-s] sampleid"
      exit 1
      ;;
  esac
done

cat ${inputfrag} | awk -v L=-${bound} -v U=${bound} '($5 >= L && $5 <= U) || ($6 >= L && $6 <= U) { print $0 }' \
    | cut -f4 > ${outputdir}/${sampleid}_filterND_${bound}.tsv

samtools view -H ${inputbam} >> ${sampleid}_filterND_${bound}.sam
samtools view ${inputbam} | grep -f ${outputdir}/${sampleid}_filterND_${bound}.tsv  >> ${outputdir}/${sampleid}_filterND_${bound}.sam
samtools view -bS -o ${outputdir}/${sampleid}_filterND_${bound}.bam ${outputdir}/${sampleid}_filterND_${bound}.sam;
rm -rf ${outputdir}/${sampleid}_filterND_${bound}.sam;

# example cmd:
# bash customFilterBAM_nucleosome_distance.sh \
# -i /media/hieunguyen/HNSD01/outdir/FragmentomicsFeatures/nextflow_output/OUTPUT/exp7_FLEN_EM_ND_2Dfeatures/9-ZMC025NB_S95001-S97001_FLEN_EM_ND.tsv \
# -b /media/hieunguyen/HNSD01/raw_data/ECD/lowDepth_BAM/9-ZMC025NB_S95001-S97001.sorted.TEST.bam -c 50 -s 9-ZMC025NB_S95001-S97001 -o .