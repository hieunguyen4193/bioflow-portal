include { REANNOTATION   } from '../subworkflows/reannotation'
include { FILTERING      } from '../subworkflows/filtering'
include { THRESHOLD      } from '../subworkflows/threshold'
include { CLUSTERING     } from '../subworkflows/clustering'
include { GERMLINES      } from '../subworkflows/germlines'
include { SHM            } from '../subworkflows/shm'
include { DIVERSITY      } from '../subworkflows/diversity'
include { GENE_USAGE_WF  } from '../subworkflows/gene_usage'
include { LINEAGE        } from '../subworkflows/lineage'
include { RENDER_REPORT  } from '../modules/render_report/main'

workflow IMMCANTATION_PIPELINE {
    take:
    ch_input   // tuple: [sample_id, subject, contig_fasta, contig_annotations]
    params

    main:
    // ── S1: IgBLAST V(D)J reannotation (always runs) ────────────────────────
    REANNOTATION(ch_input, params.species)

    // ── S2: Filter productive/functional sequences (always runs) ───────────
    FILTERING(REANNOTATION.out.db_pass)

    // ── S3: Clonal distance threshold, per subject (auto or manual) ────────
    THRESHOLD(
        FILTERING.out.functional_igh,
        params.auto_threshold,
        params.dist_threshold
    )

    // ── S4: Change-O clonal clustering, per subject (always runs) ──────────
    CLUSTERING(
        THRESHOLD.out.threshold,
        params.clone_model,
        params.clone_norm
    )

    // ── S5: Germline reconstruction, per subject (always runs) ─────────────
    GERMLINES(CLUSTERING.out.clone_pass, params.species)

    // ── S6: SHM / mutation frequency, per subject (always runs) ────────────
    SHM(GERMLINES.out.germ_pass)

    // ── S7: Clonal abundance + diversity, per subject (always runs) ────────
    DIVERSITY(GERMLINES.out.germ_pass, params.nboot)

    // ── S8: V/J gene usage, per subject (always runs) ───────────────────────
    GENE_USAGE_WF(GERMLINES.out.germ_pass)

    // ── S9: Lineage trees (optional, off by default) ────────────────────────
    if (params.run_lineage == "true") {
        LINEAGE(GERMLINES.out.germ_pass, params.lineage_min_seqs)
    }

    // ── S10: Render one HTML report per subject ─────────────────────────────
    if (params.run_report == "true") {
        ch_threshold_txt = THRESHOLD.out.threshold.map { subject, combined, threshold_txt -> tuple(subject, threshold_txt) }

        ch_report_input = SHM.out.shm_table
            .join(DIVERSITY.out.abundance_table)
            .join(DIVERSITY.out.diversity_table)
            .join(GENE_USAGE_WF.out.gene_usage_tables)
            .join(ch_threshold_txt)
        // => tuple: [subject, shm, abundance, diversity, v_usage, j_usage, threshold_txt]

        RENDER_REPORT(ch_report_input, file("${projectDir}/rmd/bcr_report.Rmd"))
    }

    emit:
    germ_pass       = GERMLINES.out.germ_pass
    shm_table       = SHM.out.shm_table
    abundance_table = DIVERSITY.out.abundance_table
    diversity_table = DIVERSITY.out.diversity_table
}
