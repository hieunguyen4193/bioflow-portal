include { LOAD_REPERTOIRES } from '../modules/load_repertoires/main'
include { EXPLORE          } from '../modules/explore/main'
include { CLONALITY        } from '../modules/clonality/main'
include { DIVERSITY        } from '../modules/diversity/main'
include { GENE_USAGE       } from '../modules/gene_usage/main'
include { CLONAL_TRACKING  } from '../modules/clonal_tracking/main'
include { OVERLAP          } from '../modules/overlap/main'
include { KMER_ANALYSIS    } from '../modules/kmer_analysis/main'
include { RENDER_REPORT    } from '../modules/render_report/main'

workflow IMMUNARCH_PIPELINE {
    take:
    ch_samplesheet   // path to samplesheet.csv
    params

    main:
    // ── S1: Load repertoires (always runs) ──────────────────────────────────
    LOAD_REPERTOIRES(ch_samplesheet)

    // ── S2: Repertoire exploration (always runs) ─────────────────────────────
    EXPLORE(LOAD_REPERTOIRES.out.immdata, params.explore_method)

    // ── S3: Clonality (always runs) ──────────────────────────────────────────
    CLONALITY(LOAD_REPERTOIRES.out.immdata, params.clonality_method)

    // ── S4: Diversity (always runs) ──────────────────────────────────────────
    DIVERSITY(LOAD_REPERTOIRES.out.immdata, params.diversity_method)

    // ── S5: Gene usage (always runs) ─────────────────────────────────────────
    GENE_USAGE(LOAD_REPERTOIRES.out.immdata, params.gene_reference, params.gene_col)

    // ── S6: Clonal tracking (optional, off by default) ───────────────────────
    if (params.run_tracking == "true") {
        CLONAL_TRACKING(LOAD_REPERTOIRES.out.immdata, params.top_n_clonotypes)
    }

    // ── S7: Repertoire overlap (always runs; self-skips for < 2 samples) ────
    OVERLAP(LOAD_REPERTOIRES.out.immdata, params.overlap_method)

    // ── S8: K-mer analysis (optional, off by default) ────────────────────────
    if (params.run_kmer == "true") {
        KMER_ANALYSIS(LOAD_REPERTOIRES.out.immdata, params.kmer_k, params.kmer_head)
    }

    // ── S9: Render HTML report ────────────────────────────────────────────────
    if (params.run_report == "true") {
        RENDER_REPORT(
            LOAD_REPERTOIRES.out.summary,
            EXPLORE.out.table,
            EXPLORE.out.plot,
            CLONALITY.out.table,
            CLONALITY.out.plot,
            DIVERSITY.out.table,
            DIVERSITY.out.plot,
            GENE_USAGE.out.table,
            GENE_USAGE.out.plot,
            OVERLAP.out.table,
            OVERLAP.out.plot,
            file("${projectDir}/rmd/immunarch_report.Rmd")
        )
    }

    emit:
    immdata = LOAD_REPERTOIRES.out.immdata
}
