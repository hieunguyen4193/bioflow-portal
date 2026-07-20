// Step 1 — IgBLAST V(D)J reannotation + merge with 10x Genomics VDJ annotations.
// Produces an AIRR rearrangement TSV (db-pass) per sample.
process IGBLAST_REANNOTATION {
    tag "${sample_id}"
    publishDir "${params.outdir}/s1_igblast/${sample_id}", mode: 'copy'

    input:
    tuple val(sample_id), val(subject), path(contig_fasta), path(contig_annotations)
    val species

    output:
    tuple val(sample_id), val(subject), path("${sample_id}_db-pass.tsv"), emit: db_pass

    script:
    def germline_dir = "/usr/local/share/germlines/imgt/${species}/vdj"
    def igblast_db    = "/usr/local/share/igblast"
    """
    AssignGenes.py igblast \\
        -s ${contig_fasta} \\
        -b ${igblast_db} \\
        --organism ${species} \\
        --loci ig \\
        --format blast \\
        --outname ${sample_id} \\
        --outdir .

    MakeDb.py igblast \\
        -i ${sample_id}_igblast.fmt7 \\
        -s ${contig_fasta} \\
        -r ${germline_dir} \\
        --10x ${contig_annotations} \\
        --extended \\
        --outname ${sample_id}
    """
}
