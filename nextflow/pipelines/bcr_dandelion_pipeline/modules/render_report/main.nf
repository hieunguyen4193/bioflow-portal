// Step 7 — Render one self-contained HTML report per subject: clonal
// network, clone size, diversity, and V gene usage.
process RENDER_REPORT {
    tag "${subject}"
    publishDir "${params.outdir}/s7_report", mode: 'copy'

    input:
    tuple val(subject), path(network_png), path(clone_size_table), path(clone_size_png), path(diversity_table), path(v_usage_table), path(v_usage_png)

    output:
    path "${subject}_bcr_dandelion_report.html", emit: report_html

    script:
    """
    cat > run_report.py << 'PYEOF'
import base64
import pandas as pd

def img_tag(path, title):
    with open(path, "rb") as f:
        b64 = base64.b64encode(f.read()).decode()
    return f"<h3>{title}</h3><img src='data:image/png;base64,{b64}' style='max-width:900px;'/>"

def table_html(path, title):
    try:
        df = pd.read_csv(path, sep="\\t", comment="#")
        if df.empty:
            return f"<h3>{title}</h3><p><em>No data.</em></p>"
        return f"<h3>{title}</h3>" + df.head(200).to_html(index=False, border=0, classes="tbl")
    except Exception as e:
        return f"<h3>{title}</h3><p><em>Could not render table: {e}</em></p>"

sections = []
sections.append(img_tag("${network_png}", "Clonal similarity network"))
sections.append(table_html("${clone_size_table}", "Clone size"))
sections.append(img_tag("${clone_size_png}", "Top clones by size"))
sections.append(table_html("${diversity_table}", "Diversity"))
sections.append(table_html("${v_usage_table}", "V gene usage"))
sections.append(img_tag("${v_usage_png}", "V gene usage"))

html = f'''<!doctype html>
<html><head><meta charset="utf-8">
<title>BCR repertoire report - Dandelion</title>
<style>
body {{ font-family: -apple-system, Helvetica, Arial, sans-serif; margin: 2rem; color: #222; }}
h1 {{ border-bottom: 2px solid #ddd; padding-bottom: .5rem; }}
h3 {{ margin-top: 2rem; }}
table.tbl {{ border-collapse: collapse; }}
table.tbl th, table.tbl td {{ border: 1px solid #ddd; padding: 4px 10px; font-size: 0.9em; }}
table.tbl th {{ background: #f5f5f5; }}
img {{ border: 1px solid #ddd; }}
</style></head>
<body>
<h1>BCR repertoire report &mdash; Dandelion</h1>
<p>Subject: <strong>${subject}</strong></p>
{"".join(sections)}
</body></html>
'''

with open("${subject}_bcr_dandelion_report.html", "w") as f:
    f.write(html)
PYEOF

    python3 run_report.py
    """
}
