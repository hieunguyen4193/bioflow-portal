while getopts "i:s:o:p:a:v:" opt; do
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
    a )
      cnafile=$OPTARG
      ;;
    v )
      covfile=$OPTARG
      ;;
    
    \? )
      echo "Usage: cmd [-i] inputfrag [-s] sampleid [-o] outputdir [-p] projectdir [-a] cnafile [-v] covfile"
      exit 1
      ;;
  esac
done

OUTPUT="${outputdir}/04_coverage_profile_features"
mkdir -p ${OUTPUT}/${sampleid}_coverage_profile

fa="${RESOURCE_DIR}/hg19.fa"
beddir="${RESOURCE_DIR}/TFBS"
#generate_coverage_profile_src="${projectdir}/src/generate_coverage_profile.py";
generate_coverage_profile_src="${projectdir}/src/generate_coverage_profile_SPEEDUP.py"
# ***** hard code: always keep the 50 <= flen <= 350
min_flen=50;
max_flen=350;

all_tfbs_beds=$(ls ${beddir}/*.Top1000sites_1000.hg19.bed);
for tfbsbed in ${all_tfbs_beds};do \
    python ${generate_coverage_profile_src} \
        --input ${inputfrag} \
        --output ${OUTPUT}/${sampleid}_coverage_profile \
        --inputbed ${tfbsbed} \
        --cna ${cnafile} \
        --cov ${covfile} \
        --mapq 30 \
        --expand_size 1000 \
        --count_mode "fragment" \
        --min_flen ${min_flen} \
        --max_flen ${max_flen} \
        --sampleid ${sampleid};
done;