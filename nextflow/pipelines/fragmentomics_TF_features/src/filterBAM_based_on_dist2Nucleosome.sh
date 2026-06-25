# export the samtools into path if not exists already.
export PATH=/Users/hieunguyen/samtools/bin:$PATH;

while getopts "i:o:n:l:u:b" opt; do
case ${opt} in
    i )
      inputbam=$OPTARG
      ;;
    o )
      outputdir=$OPTARG
      ;;
    n )
      nthreads=$OPTARG
      ;;
    l )
      lower_bound=$OPTARG
      ;;
    u )
      upper_bound=$OPTARG
      ;;   
    \? )
      echo "Usage: cmd [-i] inputbam [-o] outputdir [-n] nthreads"
      exit 1
      ;;
  esac
done

sampleid=$(echo ${inputbam} | xargs -n 1 basename);
sampleid=${sampleid%.bam*};
