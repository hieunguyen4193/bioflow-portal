include { CRAM_TO_BAM         } from '../modules/cram_to_bam/main'
include { PROCESS_BAM         } from '../modules/process_bam/main'
include { CHROMOSOME_FEATURES } from '../modules/chromosome_features/main'
include { CNA_FEATURES        } from '../modules/cna_features/main'
include { COVERAGE_PROFILE    } from '../modules/coverage_profile/main'
include { WPS_IFS_FDI         } from '../modules/wps_ifs_fdi/main'
include { RFE_FEATURES        } from '../modules/rfe_features/main'

workflow FRAGMENTOMICS {
    take:
    ch_samples  // channel: [ sampleID, path(bam_or_cram) ]

    main:

    // ── Optional step 0: CRAM → BAM ──────────────────────────────────────
    if (params.input_type == "cram") {
        ch_bam = CRAM_TO_BAM(ch_samples).bam
    } else {
        ch_bam = ch_samples
    }

    // ── Step 01: preprocess BAM ───────────────────────────────────────────
    PROCESS_BAM(ch_bam)

    ch_prep_bam  = PROCESS_BAM.out.preprocessed_bam
    ch_prep_bai  = PROCESS_BAM.out.preprocessed_bai
    ch_split     = PROCESS_BAM.out.split_chroms
    ch_frag      = PROCESS_BAM.out.frag
    ch_genomecov = PROCESS_BAM.out.genomecov

    // ── Step 02: chromosome features ─────────────────────────────────────
    if (params.run_step02 == "true") {
        CHROMOSOME_FEATURES(ch_split)
        ch_chrom = CHROMOSOME_FEATURES.out.chrom_features
    }

    // ── Step 03: CNA features ─────────────────────────────────────────────
    if (params.run_step03 == "true") {
        CNA_FEATURES(ch_prep_bam, ch_prep_bai)
        ch_cna_100kb = CNA_FEATURES.out.cna_100kb
    }

    // ── Step 04: coverage profile ─────────────────────────────────────────
    if (params.run_step04 == "true" && params.run_step03 == "true") {
        ch_cov_input = ch_frag
            .join(ch_cna_100kb, by: 0)
            .join(ch_genomecov, by: 0)
        COVERAGE_PROFILE(ch_cov_input)
    }

    // ── Step 05: WPS / IFS / FDI features ────────────────────────────────
    if (params.run_step05 == "true" && params.run_step02 == "true") {
        ch_wps_input = ch_frag.join(ch_chrom, by: 0)
        WPS_IFS_FDI(ch_wps_input)
    }

    // ── Step 06: RFE features ─────────────────────────────────────────────
    if (params.run_step06 == "true") {
        RFE_FEATURES(ch_frag)
    }
}
