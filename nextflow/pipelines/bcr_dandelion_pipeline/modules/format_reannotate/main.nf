// Step 1 — Prefix contig IDs with the sample name (ddl.pp.format_fastas), then
// reannotate V/D/J genes with IgBLAST (ddl.pp.reannotate_genes), same
// underlying reannotation approach as the Immcantation pipeline, but driven
// through Dandelion's own wrapper and data model.
process FORMAT_REANNOTATE {
    tag "${sample_id}"
    publishDir "${params.outdir}/s1_format_reannotate/${sample_id}", mode: 'copy'

    input:
    tuple val(sample_id), val(subject), path(contig_fasta), path(contig_annotations)
    val species

    output:
    tuple val(sample_id), val(subject), path("${sample_id}_reannotated.tsv"), path(contig_annotations), emit: reannotated

    script:
    """
    mkdir -p sample_dir
    cp ${contig_fasta} sample_dir/filtered_contig.fasta

    cat > run_reannotate.py << 'PYEOF'
import dandelion as ddl

ddl.pp.format_fastas(["sample_dir"], prefix=["${sample_id}"])

ddl.pp.reannotate_genes(
    ["sample_dir"],
    igblast_db="/usr/local/share/igblast",
    germline="/usr/local/share/germlines/imgt/${species}/vdj",
    org="${species}",
    loci="ig",
)

import glob
import shutil

candidates = sorted(glob.glob("sample_dir/dandelion/*igblast_db-pass.tsv")) or \\
             sorted(glob.glob("sample_dir/dandelion/*.tsv"))
if not candidates:
    raise FileNotFoundError("No reannotated AIRR TSV produced by ddl.pp.reannotate_genes")

shutil.copy(candidates[0], "${sample_id}_reannotated.tsv")
PYEOF

    python3 run_reannotate.py
    """
}
