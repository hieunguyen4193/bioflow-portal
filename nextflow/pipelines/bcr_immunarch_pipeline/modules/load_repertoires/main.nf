// Step 1 — Stage each sample's 10x contig_annotations.csv into the layout
// immunarch::repLoad() expects (a folder of per-sample files + metadata.txt),
// then load them all into one immunarch immdata object.
process LOAD_REPERTOIRES {
    publishDir "${params.outdir}/s1_load", mode: 'copy'

    input:
    path samplesheet

    output:
    path "immdata.rds",        emit: immdata
    path "sample_summary.tsv", emit: summary

    script:
    """
    cat > run_load.R << 'REOF'
suppressPackageStartupMessages(library(immunarch))

samplesheet <- read.csv("${samplesheet}", stringsAsFactors = FALSE)

dir.create("immunarch_input", showWarnings = FALSE)
meta <- data.frame(Sample = character(), Subject = character(), stringsAsFactors = FALSE)

for (i in seq_len(nrow(samplesheet))) {
  sid  <- as.character(samplesheet\$SampleID[i])
  subj <- if ("subject" %in% colnames(samplesheet)) as.character(samplesheet\$subject[i]) else NA
  if (is.na(subj) || subj == "") subj <- sid

  dest <- file.path("immunarch_input", paste0(sid, "_filtered_contig_annotations.csv"))
  file.copy(samplesheet\$contig_annotations[i], dest)
  meta <- rbind(meta, data.frame(Sample = sid, Subject = subj, stringsAsFactors = FALSE))
}
write.table(meta, file.path("immunarch_input", "metadata.txt"), sep = "\\t", row.names = FALSE, quote = FALSE)

immdata <- repLoad("immunarch_input")
saveRDS(immdata, "immdata.rds")

summary_df <- data.frame(
  Sample       = names(immdata\$data),
  n_clonotypes = sapply(immdata\$data, nrow)
)
write.table(summary_df, "sample_summary.tsv", sep = "\\t", row.names = FALSE, quote = FALSE)
REOF

    Rscript run_load.R
    """
}
