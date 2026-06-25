while getopts "i:s:o:p:c:" opt; do
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
    c )
      chromosome_features=$OPTARG
      ;;
    
    \? )
      echo "Usage: cmd [-i] inputfrag [-s] sampleid [-o] outputdir [-p] projectdir [-c] chromosome_features"
      exit 1
      ;;
  esac
done

OUTPUT="${outputdir}/05_WPS_IFS_FDI"
mkdir -p ${OUTPUT}/${sampleid}_WPS_IFS_FDI_features

WPS_IFS_FDI_aggregated_src="${projectdir}/src/WPS_IFS_FDI_aggregated.py";

beddir="${RESOURCE_DIR}/TFBS"
all_tfbs_beds=$(ls ${beddir}/*.Top1000sites_1000.hg19.bed);
mkdir -p ${sampleid}_WPS_IFS_FDI_features;

for tfbsbed in ${all_tfbs_beds};do \
    python ${WPS_IFS_FDI_aggregated_src} \
    --input ${inputfrag} \
    --output ${OUTPUT}/${sampleid}_WPS_IFS_FDI_features \
    --inputbed ${tfbsbed} \
    --window_size 120 \
    --fdi_nb_size 10 \
    --chromosome_features ${chromosome_features} \
    --expand_size 1000 \
    --sampleid ${sampleid};
done;