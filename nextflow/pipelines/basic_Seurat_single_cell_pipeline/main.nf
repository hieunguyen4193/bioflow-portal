#!/usr/bin/env nextflow
nextflow.enable.dsl = 2

include { SEURAT_PIPELINE } from './workflows/seurat_pipeline'

// ── Input files ────────────────────────────────────────────────────────────
params.barcodes              = null
params.features              = null
params.matrix                = null
params.sample_name           = "sample"

// ── Step 1: QC thresholds ──────────────────────────────────────────────────
params.min_cells             = 3
params.min_features          = 200
params.max_features          = 5000
params.max_mt_pct            = 20
params.remove_TCR_genes      = false

// ── Step skip switches (s1 always runs) ───────────────────────────────────
params.run_downsample    = "false"
params.downsample_type   = "percent"  // percent | number
params.downsample_value  = 100
params.run_s2 = "true"
params.run_s3 = "true"
params.run_s4 = "true"
params.run_s5 = "true"
params.run_s6 = "true"
params.run_s7 = "true"
params.run_s8  = "true"
params.run_s8a = "true"

// ── Step 2: Ambient RNA ────────────────────────────────────────────────────
params.ambient_method        = "decontX"   // decontX | SoupX | none

// ── Step 3: Cell filtering ("" = skip that filter) ────────────────────────
params.nFeatureRNA_floor      = ""
params.nFeatureRNA_ceiling    = ""
params.nCountRNA_floor        = ""
params.nCountRNA_ceiling      = ""
params.pct_mito_floor         = ""
params.pct_mito_ceiling       = ""
params.pct_ribo_floor         = ""
params.pct_ribo_ceiling       = ""
params.ambientRNA_thres       = ""
params.log10GenesPerUMI_thres = ""

// ── Step 4: Doublet detection ──────────────────────────────────────────────
params.doublet_csv           = "${projectDir}/assets/DoubletEstimation10X.csv"
params.remove_doublet        = false

// ── Step 5: CC pre-processing ──────────────────────────────────────────────
params.use_sctransform       = false
params.vars_to_regress       = "percent.mt"

// ── Step 6: Cell cycle scoring ─────────────────────────────────────────────
params.cc_scoring_mode       = "gene_name"    // gene_name | ensembl

// ── Step 7: Regress out ────────────────────────────────────────────────────
params.features_to_regressOut = "none"        // comma-separated list or "none"
params.regressOut_mode        = "alternative" // normal | alternative

// ── Step 8: UMAP + clustering ──────────────────────────────────────────────
params.num_PCA                   = 50
params.num_PC_used_in_UMAP       = 30
params.num_PC_used_in_Clustering = 30
params.cluster_resolution        = 0.5
params.s8_vars_to_regress        = "percent.mt"
params.s8_remove_genes           = "none"

params.outdir                = "${launchDir}/results"

workflow {
    ch_input = Channel.of([
        params.sample_name,
        file(params.barcodes),
        file(params.features),
        file(params.matrix)
    ])

    SEURAT_PIPELINE(ch_input, params)
}
