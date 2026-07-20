include { FORMAT_REANNOTATE     } from '../modules/format_reannotate/main'
include { CONTIG_QC             } from '../modules/contig_qc/main'
include { COMBINE_SUBJECT       } from '../modules/combine_subject/main'
include { FIND_CLONES           } from '../modules/find_clones/main'
include { CLONAL_NETWORK        } from '../modules/clonal_network/main'
include { CLONE_SIZE_DIVERSITY  } from '../modules/clone_size_diversity/main'
include { GENE_USAGE            } from '../modules/gene_usage/main'
include { RENDER_REPORT         } from '../modules/render_report/main'

workflow DANDELION_PIPELINE {
    take:
    ch_input   // tuple: [sample_id, subject, contig_fasta, contig_annotations]
    params

    main:
    // ── S1: Format + IgBLAST reannotation (always runs) ─────────────────────
    FORMAT_REANNOTATE(ch_input, params.species)

    // ── S2: Contig QC (always runs) ──────────────────────────────────────────
    CONTIG_QC(FORMAT_REANNOTATE.out.reannotated, params.productive_only)

    // ── Group by subject (clone definition/network run per subject) ─────────
    ch_grouped = CONTIG_QC.out.qc_pass
        .map { sample_id, subject, path -> tuple(subject, sample_id, path) }
        .groupTuple(by: 0)

    COMBINE_SUBJECT(ch_grouped)

    // ── S3: Clone definition (always runs) ───────────────────────────────────
    FIND_CLONES(COMBINE_SUBJECT.out.combined, params.identity_threshold)

    // ── S4: Clonal similarity network (always runs) ──────────────────────────
    CLONAL_NETWORK(FIND_CLONES.out.clones, params.min_network_size)

    // ── S5: Clone size + diversity (always runs) ─────────────────────────────
    CLONE_SIZE_DIVERSITY(CLONAL_NETWORK.out.clones, params.diversity_method)

    // ── S6: V gene usage (always runs) ───────────────────────────────────────
    GENE_USAGE(CLONE_SIZE_DIVERSITY.out.clones)

    // ── S7: Render per-subject HTML report ───────────────────────────────────
    if (params.run_report == "true") {
        ch_report_input = CLONAL_NETWORK.out.plot
            .join(CLONE_SIZE_DIVERSITY.out.clone_size_table)
            .join(CLONE_SIZE_DIVERSITY.out.clone_size_plot)
            .join(CLONE_SIZE_DIVERSITY.out.diversity_table)
            .join(GENE_USAGE.out.v_usage)
            .join(GENE_USAGE.out.plot)
        // => tuple: [subject, network_png, clone_size_tsv, clone_size_png, diversity_tsv, v_usage_tsv, v_usage_png]

        RENDER_REPORT(ch_report_input)
    }

    emit:
    clones = CLONE_SIZE_DIVERSITY.out.clones
}
