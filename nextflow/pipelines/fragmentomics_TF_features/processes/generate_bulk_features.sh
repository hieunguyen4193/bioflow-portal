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

fa="${RESOURCE_DIR}/hg19.fa"
nucleosome_ref="${RESOURCE_DIR}/rpr_map_Budhraja_STM2023.bed"

OUTPUT="${outputdir}"
TMPDIR="${outputdir}/TMPDIR_${sampleid}"

mkdir -p ${TMPDIR}
mkdir -p ${OUTPUT}/${sampleid}_bulk_features

EMscript="${projectdir}/src/EM.sh"
NUCLEOSOME_DISTANCEscript="${projectdir}/src/NUCLEOSOME_DISTANCE.sh"
generate_FLEN_EM_ND_2Dfeatures="${projectdir}/src/generate_FLEN_EM_ND_2Dfeatures.py"

bash ${EMscript} -i ${inputfrag} -o ${TMPDIR} -f ${fa} -s ${sampleid};
bash ${NUCLEOSOME_DISTANCEscript} -i ${inputfrag} -o ${TMPDIR} -r ${nucleosome_ref} -s ${sampleid}

cat ${TMPDIR}/${sampleid}.forward_endmotif4bp.sorted.txt | cut -f4 > ${TMPDIR}/${sampleid}.forwardEM.txt
cat ${TMPDIR}/${sampleid}.reverse_endmotif4bp.sorted.txt | cut -f4 > ${TMPDIR}/${sampleid}.reverseEM.txt
cat ${TMPDIR}/${sampleid}.forward_Nucleosome.dist.sorted.bed | cut -f10 > ${TMPDIR}/${sampleid}.forwardNucleosome.txt
cat ${TMPDIR}/${sampleid}.reverse_Nucleosome.dist.sorted.bed | cut -f10 > ${TMPDIR}/${sampleid}.reverseNucleosome.txt

paste <(zcat ${inputfrag}) \
    ${TMPDIR}/${sampleid}.forwardNucleosome.txt \
    ${TMPDIR}/${sampleid}.reverseNucleosome.txt \
    ${TMPDIR}/${sampleid}.forwardEM.txt \
    ${TMPDIR}/${sampleid}.reverseEM.txt > ${OUTPUT}/${sampleid}_FLEN_EM_ND.tsv

rm -rf ${TMPDIR}/${sampleid}.forwardEM.txt
rm -rf ${TMPDIR}/${sampleid}.reverseEM.txt
rm -rf ${TMPDIR}/${sampleid}.forwardNucleosome.txt
rm -rf ${TMPDIR}/${sampleid}.reverseNucleosome.txt
rm -rf ${TMPDIR}/${sampleid}*forward_endmotif4bp.sorted.txt
rm -rf ${TMPDIR}/${sampleid}*reverse_endmotif4bp.sorted.txt
rm -rf ${TMPDIR}/${sampleid}*forward_Nucleosome.dist.sorted.bed
rm -rf ${TMPDIR}/${sampleid}*reverse_Nucleosome.dist.sorted.bed

python ${generate_FLEN_EM_ND_2Dfeatures} \
    --input ${OUTPUT}/${sampleid}_FLEN_EM_ND.tsv \
    --output ${OUTPUT}/${sampleid}_bulk_features \
    --min_flen 50 --max_flen 350

rm -rf ${TMPDIR};

##### example cmd
# for full BAM files
# srcdir="/home/hieunguyen/src/runParallel/FragmentomicsFeatures"
# SampleSheet="${srcdir}/experiments/metadata_v8/experiment_parallel_20260331/exp10.csv"
# outputdir="/mnt/NFS_190T/DATA_HIEUNGUYEN/outputdir/metadata_v8_crop50/10_bulk_features"
# parallel --header : --colsep ',' -j 50 -a ${SampleSheet} bash 10_generate_bulk_features.sh {SampleID} {path} ${outputdir}

# for enriched BAM files
# srcdir="/home/hieunguyen/src/runParallel/FragmentomicsFeatures"
# SampleSheet="${srcdir}/experiments/metadata_v8/experiment_parallel_20260331/exp_enrich103.csv"
# outputdir="/mnt/NFS_190T/DATA_HIEUNGUYEN/outputdir/enrich_FLEN/enrich103_bulkFeatures"
# parallel --header : --colsep ',' -j 50 -a ${SampleSheet} bash 10_generate_bulk_features.sh {SampleID} {path} ${outputdir}

