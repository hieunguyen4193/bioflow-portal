// Step 5 — Clone size distribution (ddl.tl.clone_size) and repertoire
// diversity (ddl.tl.clone_diversity) per subject.
process CLONE_SIZE_DIVERSITY {
    tag "${subject}"
    publishDir "${params.outdir}/s5_clone_size_diversity/${subject}", mode: 'copy'

    input:
    tuple val(subject), path(clones_tsv)
    val diversity_method

    output:
    tuple val(subject), path(clones_tsv),                       emit: clones
    tuple val(subject), path("${subject}_clone_size.tsv"),      emit: clone_size_table
    tuple val(subject), path("${subject}_clone_size.png"),      emit: clone_size_plot
    tuple val(subject), path("${subject}_diversity.tsv"),       emit: diversity_table

    script:
    """
    cat > run_size_diversity.py << 'PYEOF'
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd
import dandelion as ddl

def placeholder_png(path, message):
    fig, ax = plt.subplots(figsize=(6, 3))
    ax.text(0.5, 0.5, message, ha="center", va="center", wrap=True)
    ax.axis("off")
    fig.savefig(path, dpi=150, bbox_inches="tight")

df = pd.read_csv("${clones_tsv}", sep="\\t")
vdj = ddl.Dandelion(df)

clone_col = "clone_id" if "clone_id" in vdj.data.columns else None
if clone_col is None:
    raise ValueError("No clone_id column found; run FIND_CLONES first.")

try:
    ddl.tl.clone_size(vdj, key_added="clone_id_size")
    size_col = "clone_id_size" if "clone_id_size" in vdj.data.columns else None
except Exception as e:
    print(f"ddl.tl.clone_size() failed, falling back to manual counts: {e}")
    size_col = None

if size_col is not None:
    size_table = vdj.data[[clone_col, size_col]].drop_duplicates()
else:
    counts = vdj.data.groupby(clone_col).size().reset_index(name="clone_id_size")
    size_table = counts

size_table = size_table.sort_values("clone_id_size", ascending=False)
size_table.to_csv("${subject}_clone_size.tsv", sep="\\t", index=False)

top = size_table.head(30)
fig, ax = plt.subplots(figsize=(9, 5))
ax.bar(top[clone_col].astype(str), top["clone_id_size"], color="steelblue")
ax.set_xticklabels(top[clone_col].astype(str), rotation=90, fontsize=6)
ax.set_xlabel("Clone ID")
ax.set_ylabel("Size (n cells)")
ax.set_title("${subject}: top 30 clones by size")
fig.tight_layout()
fig.savefig("${subject}_clone_size.png", dpi=150, bbox_inches="tight")

metric = "${diversity_method}"
try:
    div = ddl.tl.clone_diversity(vdj, method=metric)
    if hasattr(div, "to_csv"):
        div.to_csv("${subject}_diversity.tsv", sep="\\t")
    else:
        with open("${subject}_diversity.tsv", "w") as f:
            f.write(f"metric\\tvalue\\n{metric}\\t{div}\\n")
except Exception as e:
    print(f"ddl.tl.clone_diversity() failed: {e}")
    with open("${subject}_diversity.tsv", "w") as f:
        f.write(f"# diversity ({metric}) unavailable: {e}\\n")
PYEOF

    python3 run_size_diversity.py
    """
}
