// Step 4 — Build Dandelion's signature clonal similarity network
// (ddl.tl.generate_network) and plot it, colored by clone size. This is
// Dandelion's most distinctive feature relative to the other three BCR
// pipelines (nearest-neighbor clustering in Immcantation, identity/similarity
// clonotypes in scirpy, simple grouping in immunarch).
process CLONAL_NETWORK {
    tag "${subject}"
    publishDir "${params.outdir}/s4_clonal_network/${subject}", mode: 'copy'

    input:
    tuple val(subject), path(clones_tsv)
    val min_size

    output:
    tuple val(subject), path(clones_tsv),          emit: clones
    tuple val(subject), path("${subject}_network.png"),          emit: plot
    tuple val(subject), path("${subject}_network_nodes.tsv"),    emit: nodes

    script:
    """
    cat > run_network.py << 'PYEOF'
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

try:
    ddl.tl.generate_network(vdj, min_size=${min_size})

    graph = vdj.graph[0] if isinstance(vdj.graph, (tuple, list)) else vdj.graph
    layout = vdj.layout[0] if isinstance(vdj.layout, (tuple, list)) else vdj.layout

    import networkx as nx
    fig, ax = plt.subplots(figsize=(7, 7))
    sizes = df.groupby("clone_id").size().to_dict() if "clone_id" in df.columns else {}
    node_colors = [sizes.get(n, 1) for n in graph.nodes()]
    nx.draw_networkx_nodes(graph, pos=layout, node_size=15, node_color=node_colors, cmap="viridis", ax=ax)
    nx.draw_networkx_edges(graph, pos=layout, alpha=0.3, width=0.5, ax=ax)
    ax.set_title("${subject}: clonal similarity network")
    ax.axis("off")
    fig.savefig("${subject}_network.png", dpi=150, bbox_inches="tight")

    nodes_df = pd.DataFrame({"node": list(graph.nodes())})
    nodes_df.to_csv("${subject}_network_nodes.tsv", sep="\\t", index=False)

except Exception as e:
    print(f"Falling back to placeholder network plot: {e}")
    placeholder_png("${subject}_network.png", f"clonal network unavailable:\\n{e}")
    pd.DataFrame({"node": []}).to_csv("${subject}_network_nodes.tsv", sep="\\t", index=False)
PYEOF

    python3 run_network.py
    """
}
