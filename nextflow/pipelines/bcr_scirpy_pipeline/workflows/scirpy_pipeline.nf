include { LOAD_10X_VDJ            } from '../modules/load_10x_vdj/main'
include { CHAIN_QC_FILTER         } from '../modules/chain_qc_filter/main'
include { DEFINE_CLONOTYPES       } from '../modules/define_clonotypes/main'
include { CLONAL_EXPANSION        } from '../modules/clonal_expansion/main'
include { DIVERSITY               } from '../modules/diversity/main'
include { REPERTOIRE_OVERLAP      } from '../modules/repertoire_overlap/main'
include { GENE_USAGE_SPECTRATYPE  } from '../modules/gene_usage_spectratype/main'
include { RENDER_REPORT           } from '../modules/render_report/main'

workflow SCIRPY_PIPELINE {
    take:
    ch_samplesheet   // path to samplesheet.csv
    params

    main:
    // ── S1: Load + concatenate 10x VDJ data (always runs) ──────────────────
    LOAD_10X_VDJ(ch_samplesheet)

    // ── S2: Chain QC + BCR/pairing filtering (always runs) ──────────────────
    CHAIN_QC_FILTER(
        LOAD_10X_VDJ.out.adata,
        params.remove_multichain,
        params.require_paired
    )

    // ── S3: Clonotype definition (always runs) ──────────────────────────────
    DEFINE_CLONOTYPES(
        CHAIN_QC_FILTER.out.adata,
        params.clustering_mode,
        params.sequence,
        params.metric,
        params.receptor_arms,
        params.dual_ir
    )

    // ── S4: Clonal expansion (always runs) ───────────────────────────────────
    CLONAL_EXPANSION(DEFINE_CLONOTYPES.out.adata)

    // ── S5: Alpha diversity (always runs) ────────────────────────────────────
    DIVERSITY(CLONAL_EXPANSION.out.adata, params.diversity_metric)

    // ── S6: Repertoire overlap (always runs; self-skips for < 2 samples) ────
    REPERTOIRE_OVERLAP(DIVERSITY.out.adata, params.overlap_metric)

    // ── S7: Gene usage + spectratype (always runs) ───────────────────────────
    GENE_USAGE_SPECTRATYPE(DIVERSITY.out.adata)

    // ── S8: Render HTML report ────────────────────────────────────────────────
    if (params.run_report == "true") {
        RENDER_REPORT(
            LOAD_10X_VDJ.out.summary,
            CHAIN_QC_FILTER.out.summary,
            CHAIN_QC_FILTER.out.plot,
            DEFINE_CLONOTYPES.out.summary,
            CLONAL_EXPANSION.out.summary,
            CLONAL_EXPANSION.out.plot,
            DIVERSITY.out.summary,
            DIVERSITY.out.plot,
            REPERTOIRE_OVERLAP.out.summary,
            REPERTOIRE_OVERLAP.out.plot,
            GENE_USAGE_SPECTRATYPE.out.v_usage_heavy,
            GENE_USAGE_SPECTRATYPE.out.v_usage_light,
            GENE_USAGE_SPECTRATYPE.out.spectratype,
            GENE_USAGE_SPECTRATYPE.out.plot
        )
    }

    emit:
    adata           = DIVERSITY.out.adata
    clonotype_table = DEFINE_CLONOTYPES.out.summary
}
