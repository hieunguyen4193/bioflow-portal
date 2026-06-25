while getopts "i:s:o:p:" opt; do
case ${opt} in
    i )
      inputbam=$OPTARG
      ;;
    s )
      sampleid=$OPTARG
      ;;
    o )
      outdir=$OPTARG
      ;;
    p )
      projectdir=$OPTARG
      ;;
    \? )
      echo "Usage: cmd [-i] inputbam [-s] sampleid [-o] outdir [-p] projectdir"
      exit 1
      ;;
  esac
done

# ***** export path to samtools installed in the docker image. 
export PATH=/home/dockerUser/samtools/bin:$PATH;

filterbamsh="${projectdir}/src/filterBAM.sh"
outputdir=${outdir}/${sampleid};
mkdir -p ${outputdir};

if [ -f "${outputdir}/${sampleid}_lt150_or_gt175.filtered.bam" ]; then
    echo "Output file already exists. Skipping filtering steps..."
    exit 0
else 
    # ***** filter reads: keep fragments < 150 bp *****
    echo -e "filtering BAM file 50 - 150 for ${sampleid}..."
    bash ${filterbamsh} -i ${inputbam} -o ${outputdir} -s ${sampleid} -n 12 -l 50 -u 150;
    samtools index ${outputdir}/${sampleid}_50_150.filtered.bam

    # ***** filter reads: keep fragments < 150 bp or > 175bp *****
    echo -e "filtering BAM file 175 - 300 for ${sampleid}..."
    bash ${filterbamsh} -i ${inputbam} -o ${outputdir} -s ${sampleid} -n 12 -l 175 -u 350;
    samtools index ${outputdir}/${sampleid}_175_350.filtered.bam

    # ***** merge these bam file to get bam file containing all fragments < 150 bp or > 175bp *****
    echo -e "merging bam files for ${sampleid}..."
    samtools merge -@ 12 \
        ${outputdir}/${sampleid}_lt150_or_gt175.filtered.bam \
        ${outputdir}/${sampleid}_50_150.filtered.bam \
        ${outputdir}/${sampleid}_175_350.filtered.bam;
    samtools index ${outputdir}/${sampleid}_lt150_or_gt175.filtered.bam;
fi

# EOF