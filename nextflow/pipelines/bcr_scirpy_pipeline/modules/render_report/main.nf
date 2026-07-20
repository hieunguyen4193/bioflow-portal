// Step 8 — Assemble a single static HTML report embedding every summary
// table and plot produced by the earlier steps (base64-embedded PNGs, no
// external assets, so the report is a single self-contained file).
process RENDER_REPORT {
    publishDir "${params.outdir}/s8_report", mode: 'copy'

    input:
    path sample_summary
    path chain_qc_summary
    path chain_pairing_png
    path clonotype_summary
    path clonal_expansion_summary
    path clonal_expansion_png
    path diversity_summary
    path diversity_png
    path repertoire_overlap_tsv
    path repertoire_overlap_png
    path v_usage_heavy
    path v_usage_light
    path spectratype_tsv
    path spectratype_png

    output:
    path "bcr_scirpy_report.html", emit: report_html

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
        return f"<h3>{title}</h3>" + df.to_html(index=False, border=0, classes="tbl")
    except Exception as e:
        return f"<h3>{title}</h3><p><em>Could not render table: {e}</em></p>"

sections = []
sections.append(table_html("${sample_summary}", "Sample summary"))
sections.append(table_html("${chain_qc_summary}", "Chain QC (pairing categories)"))
sections.append(img_tag("${chain_pairing_png}", "Chain pairing by sample"))
sections.append(table_html("${clonotype_summary}", "Clonotype summary"))
sections.append(table_html("${clonal_expansion_summary}", "Clonal expansion"))
sections.append(img_tag("${clonal_expansion_png}", "Clonal expansion by sample"))
sections.append(table_html("${diversity_summary}", "Alpha diversity"))
sections.append(img_tag("${diversity_png}", "Alpha diversity by sample"))
sections.append(table_html("${repertoire_overlap_tsv}", "Repertoire overlap"))
sections.append(img_tag("${repertoire_overlap_png}", "Repertoire overlap heatmap"))
sections.append(table_html("${v_usage_heavy}", "V gene usage — heavy chain (VDJ_1)"))
sections.append(table_html("${v_usage_light}", "V gene usage — light chain (VJ_1)"))
sections.append(table_html("${spectratype_tsv}", "CDR3 length spectratype"))
sections.append(img_tag("${spectratype_png}", "CDR3 length spectratype"))

html = f'''<!doctype html>
<html><head><meta charset="utf-8">
<title>BCR repertoire report - scirpy</title>
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
<h1>BCR repertoire report &mdash; scirpy</h1>
{"".join(sections)}
</body></html>
'''

with open("bcr_scirpy_report.html", "w") as f:
    f.write(html)
PYEOF

    python3 run_report.py
    """
}
