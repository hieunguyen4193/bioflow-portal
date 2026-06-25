while getopts "i:s:o:p:" opt; do
case ${opt} in
    i )
      inputbam=$OPTARG
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
      echo "Usage: cmd [-i] inputbam [-s] sampleid [-o] outputdir [-p] projectdir"
      exit 1
      ;;
  esac
done

OUTPUT="${outputdir}/03_CNA_for_coverage_profile"
rscript_cna="${projectdir}/src/calculate_CNA.R";

mkdir -p ${OUTPUT}/${sampleid}

bin100kb_file="${projectdir}/CNAbins/bin100kb.rds";
bin1M_file="${projectdir}/CNAbins/bin1M.rds";

Rscript ${rscript_cna} --input ${inputbam} --output ${OUTPUT}/${sampleid} --bin ${bin100kb_file} --sampleid ${sampleid};    
Rscript ${rscript_cna} --input ${inputbam} --output ${OUTPUT}/${sampleid} --bin ${bin1M_file} --sampleid ${sampleid};