// Step 3 — Determine the clonal assignment distance threshold.
// When auto_threshold is true: SHazaM distToNearest + findThreshold(method="density")
// on the heavy-chain junction distances. Otherwise the user-supplied
// dist_threshold is used as-is (still written out so DEFINE_CLONES has one input shape).
process SHAZAM_THRESHOLD {
    tag "${subject}"
    publishDir "${params.outdir}/s3_shazam_threshold/${subject}", mode: 'copy'

    input:
    tuple val(subject), path(combined_igh_tsv)
    val auto_threshold
    val manual_threshold

    output:
    tuple val(subject), path(combined_igh_tsv), path("${subject}_threshold.txt"), emit: threshold
    path "${subject}_threshold_hist.png",                                        emit: plot, optional: true

    script:
    """
    cat > run_threshold.R << 'REOF'
suppressPackageStartupMessages({
  library(shazam)
  library(alakazam)
  library(airr)
  library(ggplot2)
})

db <- airr::read_rearrangement("${combined_igh_tsv}")

auto <- tolower("${auto_threshold}") == "true"
manual_value <- suppressWarnings(as.numeric("${manual_threshold}"))

if (auto && nrow(db) >= 10) {
  dist <- distToNearest(
    db,
    sequenceColumn = "junction",
    vCallColumn    = "v_call",
    jCallColumn    = "j_call",
    model          = "ham",
    normalize      = "len",
    nproc          = 1
  )
  th_out <- tryCatch(
    findThreshold(dist\$dist_nearest, method = "density"),
    error = function(e) NULL
  )
  threshold <- if (!is.null(th_out) && !is.na(th_out@threshold)) th_out@threshold else manual_value
  if (is.na(threshold)) threshold <- 0.15

  p <- ggplot(dist, aes(x = dist_nearest)) +
    geom_histogram(binwidth = 0.01, fill = "steelblue", color = "white") +
    geom_vline(xintercept = threshold, color = "red", linetype = "dashed") +
    theme_bw() +
    ggtitle(paste0("${subject}: nearest-neighbor distance (threshold = ", round(threshold, 4), ")"))
  ggsave("${subject}_threshold_hist.png", p, width = 7, height = 5, dpi = 150)
} else {
  threshold <- if (!is.na(manual_value)) manual_value else 0.15
  message("Using manual/fallback threshold: ", threshold)
}

writeLines(as.character(threshold), "${subject}_threshold.txt")
REOF

    Rscript run_threshold.R
    """
}
