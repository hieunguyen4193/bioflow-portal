"""
Small helper utilities shared across the pipeline's Python scripts.
Python equivalent of src/helper_functions.R from the Seurat/R pipeline
(which defined `%ni%` and `create_dt()`).
"""

import base64
import io


def create_dt_html(df, table_id="dt"):
    """
    Render a pandas DataFrame as an interactive, sortable/searchable HTML
    table using the DataTables.net JS library loaded from CDN — the same
    library used by R's `DT::datatable()` (create_dt() in helper_functions.R).
    Returns a self-contained HTML <div> + <script> block.
    """
    table_html = df.to_html(
        table_id=table_id, index=False, escape=True, classes="display compact"
    )
    return f"""
<div>
{table_html}
</div>
<script>
$(document).ready(function() {{
    $('#{table_id}').DataTable({{
        dom: 'Blfrtip',
        buttons: ['copy', 'csv', 'excel', 'pdf', 'print'],
        lengthMenu: [[10, 25, 50, -1], [10, 25, 50, "All"]]
    }});
}});
</script>
"""


def fig_to_base64_img(fig, dpi=150):
    """Embed a matplotlib figure directly into an HTML report as a base64 <img>."""
    buf = io.BytesIO()
    fig.savefig(buf, format="png", dpi=dpi, bbox_inches="tight")
    buf.seek(0)
    encoded = base64.b64encode(buf.read()).decode("utf-8")
    return f'<img src="data:image/png;base64,{encoded}" style="max-width:100%;">'
