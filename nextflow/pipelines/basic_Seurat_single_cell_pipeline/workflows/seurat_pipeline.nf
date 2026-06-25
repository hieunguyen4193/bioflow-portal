include { QC_AND_SEURAT            } from '../subworkflows/qc_and_seurat'
include { DOWNSAMPLE_WF            } from '../subworkflows/downsample'
include { AMBIENT_CORRECTION       } from '../subworkflows/ambient_correction'
include { FILTER_CELLS_WF          } from '../subworkflows/filter_cells'
include { DOUBLET_DETECTION_WF     } from '../subworkflows/doublet_detection'
include { CELL_CYCLE_SCORING_WF    } from '../subworkflows/cell_cycle_scoring'
include { CELL_CYCLE_SCORING_S6_WF } from '../subworkflows/cell_cycle_scoring_s6'
include { REGRESS_OUT_WF           } from '../subworkflows/regress_out'
include { UMAP_CLUSTERING_WF       } from '../subworkflows/umap_clustering'

workflow SEURAT_PIPELINE {
    take:
    ch_input
    params

    main:
    // ── Step 1: Create Seurat object (always runs) ──────────────────────────
    QC_AND_SEURAT(
        ch_input,
        params.min_cells,
        params.min_features,
        params.max_features,
        params.max_mt_pct,
        params.remove_TCR_genes
    )

    // ── Step 1b: Downsampling (optional) ───────────────────────────────────
    if (params.run_downsample == "true") {
        DOWNSAMPLE_WF(
            QC_AND_SEURAT.out.seurat_rds,
            params.downsample_type,
            params.downsample_value
        )
        ch_s2_input = DOWNSAMPLE_WF.out.seurat_rds
    } else {
        ch_s2_input = QC_AND_SEURAT.out.seurat_rds
    }

    // ── Step 2: Ambient RNA decontamination ─────────────────────────────────
    if (params.run_s2 == "true" && params.ambient_method != "none") {
        AMBIENT_CORRECTION(
            ch_s2_input,
            params.ambient_method
        )
        ch_s3_input = AMBIENT_CORRECTION.out.seurat_rds
    } else {
        ch_s3_input = ch_s2_input
    }

    // ── Step 3: Cell filtering ──────────────────────────────────────────────
    if (params.run_s3 == "true") {
        FILTER_CELLS_WF(
            ch_s3_input,
            params.nFeatureRNA_floor,
            params.nFeatureRNA_ceiling,
            params.nCountRNA_floor,
            params.nCountRNA_ceiling,
            params.pct_mito_floor,
            params.pct_mito_ceiling,
            params.pct_ribo_floor,
            params.pct_ribo_ceiling,
            params.ambientRNA_thres,
            params.log10GenesPerUMI_thres
        )
        ch_s4_input  = FILTER_CELLS_WF.out.seurat_rds
        ch_qc_table  = FILTER_CELLS_WF.out.qc_table
    } else {
        ch_s4_input  = ch_s3_input
        ch_qc_table  = Channel.empty()
    }

    // ── Step 4: Doublet detection ───────────────────────────────────────────
    if (params.run_s4 == "true") {
        ch_doublet_csv = Channel.fromPath(params.doublet_csv)
        DOUBLET_DETECTION_WF(
            ch_s4_input,
            ch_doublet_csv,
            params.remove_doublet
        )
        ch_s5_input = DOUBLET_DETECTION_WF.out.seurat_rds
    } else {
        ch_s5_input = ch_s4_input
    }

    // ── Step 5: Pre-cell-cycle normalisation / PCA ──────────────────────────
    if (params.run_s5 == "true") {
        CELL_CYCLE_SCORING_WF(
            ch_s5_input,
            params.use_sctransform,
            params.vars_to_regress
        )
        ch_s6_input = CELL_CYCLE_SCORING_WF.out.seurat_rds
    } else {
        ch_s6_input = ch_s5_input
    }

    // ── Step 6: Cell cycle scoring ──────────────────────────────────────────
    if (params.run_s6 == "true") {
        CELL_CYCLE_SCORING_S6_WF(
            ch_s6_input,
            params.cc_scoring_mode
        )
        ch_s7_input = CELL_CYCLE_SCORING_S6_WF.out.seurat_rds
    } else {
        ch_s7_input = ch_s6_input
    }

    // ── Step 7: Regress out ─────────────────────────────────────────────────
    if (params.run_s7 == "true") {
        REGRESS_OUT_WF(
            ch_s7_input,
            params.features_to_regressOut,
            params.regressOut_mode
        )
        ch_s8_input = REGRESS_OUT_WF.out.seurat_rds
    } else {
        ch_s8_input = ch_s7_input
    }

    // ── Step 8: UMAP + clustering ───────────────────────────────────────────
    if (params.run_s8 == "true") {
        UMAP_CLUSTERING_WF(
            ch_s8_input,
            params.use_sctransform,
            params.num_PCA,
            params.num_PC_used_in_UMAP,
            params.num_PC_used_in_Clustering,
            params.cluster_resolution,
            params.s8_vars_to_regress,
            params.s8_remove_genes
        )
        ch_final = UMAP_CLUSTERING_WF.out.seurat_rds
    } else {
        ch_final = ch_s8_input
    }

    emit:
    seurat_rds = ch_final
    qc_table   = ch_qc_table
}
