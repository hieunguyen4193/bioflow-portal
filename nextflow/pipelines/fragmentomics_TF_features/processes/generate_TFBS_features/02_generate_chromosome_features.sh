while getopts "i:s:o:p:" opt; do
case ${opt} in
    i )
      inputSplitChroms=$OPTARG
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
      echo "Usage: cmd [-i] inputSplitChroms [-s] sampleid [-o] outputdir [-p] projectdir"
      exit 1
      ;;
  esac
done

OUTPUT="${outputdir}/02_chromosome_features"
mkdir -p ${OUTPUT}

py_chromosome_features="${projectdir}/src/chromosome_features.py";
python ${py_chromosome_features} \
    --input ${inputSplitChroms} \
    --output ${OUTPUT} \
    --sampleid ${sampleid};

