while getopts "i:s:o:f:c:" opt; do
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
    f )
      inputMin=$OPTARG
      ;;
    c )
      inputMax=$OPTARG
      ;;
      
   \? )
      echo "Usage: cmd [-i] inputfrag [-s] sampleid [-o] outdir [-f] inputMin [-c] inputMax"
      exit 1
      ;;
  esac
done

# ***** for this filtering process, we need the "${sampleid}_FLEN_EM_ND.tsv" input
# ***** from the process generate_bulk_features.sh.

# ***** export path to samtools installed in the docker image. 
export PATH=/home/dockerUser/samtools/bin:$PATH;

awk -v min=${inputMin} -v max=${inputMax} 'BEGIN{OFS="\t"} ($6 >= min && $6 <= max) || ($7 >= min && $7 <= max)' ${inputfrag} \
    > "${outputdir}/${sampleid}.filteredND_${inputMin}_${inputMax}.tsv"
