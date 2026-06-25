while getopts "i:s:o:b:" opt; do
case ${opt} in
    i )
      inputbam=$OPTARG
      ;;
    s )
      sampleid=$OPTARG
      ;;
    b )
      bedfile=$OPTARG
      ;;
    o )
      outputdir=$OPTARG
      ;;
   \? )
      echo "Usage: cmd [-i] inputbam [-s] sampleid [-o] outdir [-b] bedfile"
      exit 1
      ;;
  esac
done

# ***** export path to samtools installed in the docker image. 
export PATH=/home/dockerUser/samtools/bin:$PATH;

bedname=$(basename "${bedfile}" .bed)
mkdir -p "${outputdir}/${bedname}"

echo "Running BED file filter: ${bedname}..."

samtools view -b "${inputbam}" -L "${bedfile}" > "${outputdir}/${bedname}/${sampleid}.bam"
samtools index "${outputdir}/${bedname}/${sampleid}.bam"