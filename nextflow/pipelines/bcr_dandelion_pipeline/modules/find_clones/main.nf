// Step 3 — Clone definition per subject (ddl.tl.find_clones): groups cells
// into clones using V/J gene concordance and CDR3 sequence identity above
// the given threshold.
process FIND_CLONES {
    tag "${subject}"
    publishDir "${params.outdir}/s3_find_clones/${subject}", mode: 'copy'

    input:
    tuple val(subject), path(combined_tsv)
    val identity_threshold

    output:
    tuple val(subject), path("${subject}_clones.tsv"), emit: clones

    script:
    """
    cat > run_find_clones.py << 'PYEOF'
import pandas as pd
import dandelion as ddl

df = pd.read_csv("${combined_tsv}", sep="\\t")
vdj = ddl.Dandelion(df)

ddl.tl.find_clones(vdj, identity=${identity_threshold}, key_added="clone_id")

vdj.data.to_csv("${subject}_clones.tsv", sep="\\t", index=False)
PYEOF

    python3 run_find_clones.py
    """
}
