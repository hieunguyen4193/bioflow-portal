while getopts "i:s:o:p:" opt; do
case ${opt} in
    i )
      short_bam=$OPTARG
      ;;
    j )
      long_bam=$OPTARG
      ;;
    f )
      full_bam=$OPTARG
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
      echo "Usage: cmd [-i] short_bam [-j] long_bam [-f] full_bam [-s] sampleid [-o] outputdir [-p] projectdir"
      exit 1
      ;;
  esac
done

OUTPUT="${outputdir}"
mkdir -p ${OUTPUT}/${sampleid}_binwise_features
binwise_Rscript="${projectdir}/src/generate_binwise_features.R"

Rscript ${binwise_Rscript} \
    -s ${short_bam} \
    -l ${long_bam} \
    -f ${full_bam} \
    -o ${OUTPUT}/${sampleid}_binwise_features \
    -i ${sampleid}

