process RENDER_REPORT {
    tag "${sample}"
    publishDir "${params.outdir}/s8a_report", mode: "copy"

    input:
    tuple val(sample), path(h5ad)
    path(report_script)
    path(helper_functions)
    path(cc_genes)

    output:
    path("${sample}_preliminary_analysis.html"), emit: report_html

    script:
    """
    python3 render_report.py \\
        --h5ad               "${h5ad}" \\
        --sample             "${sample}" \\
        --outdir             . \\
        --cluster_resolution "${params.cluster_resolution}"
    """
}
