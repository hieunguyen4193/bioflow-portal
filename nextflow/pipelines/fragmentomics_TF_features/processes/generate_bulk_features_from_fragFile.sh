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

OUTPUT="${outputdir}"
mkdir -p ${OUTPUT}/${sampleid}_bulk_features
generate_FLEN_EM_ND_2Dfeatures="${projectdir}/src/generate_FLEN_EM_ND_2Dfeatures.py"
python ${generate_FLEN_EM_ND_2Dfeatures} \
    --input ${inputfrag} \
    --output ${OUTPUT}/${sampleid}_bulk_features \
    --min_flen 50 --max_flen 350
