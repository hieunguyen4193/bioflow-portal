inputCRAM=$1
outputdir=$2
ref_genome=$3

filename=$(echo $inputCRAM | xargs -n 1 basename);
filename=${filename%.cram*}.bam;

# a simple one line samtools command to convert the input BAM file to CRAM format using the reference genome hg19
samtools view -b -T ${ref_genome} -o ${outputdir}/${filename} ${inputCRAM};