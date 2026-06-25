inputBAM=$1
output_CRAM=$2
ref_genome=$3

# a simple one line samtools command to convert the input BAM file to CRAM format using the reference genome hg19
samtools view -T ${ref_genome} -C -o ${output_CRAM} ${inputBAM};