while getopts "i:s:o:p:" opt; do
case ${opt} in
    i )
      inputfrag=$OPTARG
      ;;
    s )
      sampleid=$OPTARG
      ;;
    o )
      outputdir=$OPTARG
      ;;
    p )
      projectdir=$OPTARG
      ;;
    \? )
      echo "Usage: cmd [-i] inputfrag [-s] sampleid [-o] outputdir [-p] projectdir"
      exit 1
      ;;
  esac
done

OUTPUT="${outputdir}/06_RFE_features"
mkdir -p ${OUTPUT}/${sampleid}_RFE_features

beddir="${RESOURCE_DIR}/TFBS"
fa_file="${RESOURCE_DIR}/hg19.fa"
# ***** use the new script *****
generate_RFE_features_src="${projectdir}/src/RFE_combined_enhanced.py";

# generate_RFE_features_src="${projectdir}/src/RFE_combine.py";

all_tfbs_beds=$(ls ${beddir}/*.Top1000sites_1000.hg19.bed);
mkdir -p ${sampleid}_RFE_features;
for tfbsbed in ${all_tfbs_beds};do \
    python ${generate_RFE_features_src} \
    --input ${inputfrag} \
    --output ${OUTPUT}/${sampleid}_RFE_features \
    --fa ${fa_file} \
    --inputbed ${tfbsbed} \
    --min_flen 50 \
    --max_flen 350 \
    --rfe --fld \
    --sampleid ${sampleid};
done;