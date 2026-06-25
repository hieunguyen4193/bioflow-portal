while getopts "i:s:o:p:n:q:w:e:r:f:x:m:" opt; do
case ${opt} in
    i ) inputbam=$OPTARG ;;
    s ) sampleid=$OPTARG ;;
    o ) outputdir=$OPTARG ;;
    p ) projectdir=$OPTARG ;;
    n ) nthreads=$OPTARG ;;
    q ) short_lower=$OPTARG ;;
    w ) short_upper=$OPTARG ;;
    e ) long_lower=$OPTARG ;;
    r ) long_upper=$OPTARG ;;
    f ) min_flen=$OPTARG ;;
    x ) max_flen=$OPTARG ;;
    m ) markdup=$OPTARG ;;
    \? )
      echo "Usage: cmd [-i] inputbam [-s] sampleid [-o] outputdir [-p] projectdir [-n] nthreads [-q] short_lower [-w] short_upper [-e] long_lower [-r] long_upper [-f] min_flen [-x] max_flen [-m] markdup"
      exit 1
      ;;
  esac
done

# defaults
nthreads=${nthreads:-4}
short_lower=${short_lower:-50}
short_upper=${short_upper:-150}
long_lower=${long_lower:-151}
long_upper=${long_upper:-350}
min_flen=${min_flen:-50}
max_flen=${max_flen:-350}
markdup=${markdup:-false}

# ***** export path to samtools installed in the docker image. 
export PATH=/home/dockerUser/samtools/bin:$PATH;

OUTPUT="${outputdir}/OUTPUT/01_processed_BAM_files"
CHECKDIR=${outputdir}/CHECKDIR

fa="${RESOURCE_DIR}/hg19.fa"
nucleosome_ref="${RESOURCE_DIR}/rpr_map_EXP0779.bed"
beddir="${RESOURCE_DIR}/TFBS"

bin100kb_file="${projectdir}/CNAbins/bin100kb.rds";
bin1M_file="${projectdir}/CNAbins/bin1M.rds";

mkdir -p ${OUTPUT};
mkdir -p ${CHECKDIR} 
mkdir -p ${OUTPUT}/${sampleid}

src_preprocess_BAM_files="${projectdir}/src/preprocess_BAM_files.sh";
bam2bed="${projectdir}/src/bam2bed.py";
parse_genomeCov="${projectdir}/src/parse_genomeCov_from_bedtools.py";

targeted_region="Full";

bash ${src_preprocess_BAM_files} \
    -i ${inputbam} \
    -o ${OUTPUT}/${sampleid} \
    -n ${nthreads} \
    -q ${short_lower} \
    -w ${short_upper} \
    -e ${long_lower} \
    -r ${long_upper} \
    -c ${CHECKDIR} \
    -m ${markdup} \
    -t ${targeted_region} \
    -s ${sampleid} \
    -b ${bam2bed} \
    -p ${parse_genomeCov};


# ***** example commands *****
# SampleSheet="${projectdir}/experiments/metadata_v8/official_SampleSheets/02_run_pipeline_for_existing_bam_files.csv"
# projectdir=""
# outputdir=""
# parallel --header : --colsep ',' -j 150 -a ${SampleSheet} \
#     bash 02_run_pipeline_for_existing_bam_files_PREPROCESS_BAM_parallel.sh -s {SampleID} -i {path} -o ${outputdir} -p ${projectdir}