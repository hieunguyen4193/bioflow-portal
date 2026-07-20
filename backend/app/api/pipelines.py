"""Static registry of available pipelines."""
import os
from fastapi import APIRouter, HTTPException
from fastapi.responses import PlainTextResponse

router = APIRouter(prefix="/pipelines", tags=["pipelines"])

PIPELINES_BASE = os.environ.get(
    "PIPELINES_BASE",
    "/nextflow/pipelines",
)

PIPELINE_REGISTRY = {
    "fragmentomics_TF_features": {
        "name": "Fragmentomics — TF and Enrichment Features",
        "description": "Generates cfDNA fragmentomics features (chromosome, CNA, coverage profile, WPS/IFS/FDI, RFE) from WGS BAM or CRAM files.",
        "readme": "fragmentomics_TF_features/README.md",
        "input_mode": "samplesheet",   # differs from the default "files" mode
        "input_files": [
            {"key": "samplesheet", "label": "samplesheet.csv  (SampleID, Path columns)"},
        ],
        "steps": [
            {
                "key": "step0",
                "label": "Step 0 — CRAM to BAM conversion",
                "run_key": None,   # controlled by input_type param, not a toggle
                "params": [
                    {"key": "input_type", "label": "Input file type", "type": "select", "default": "bam", "options": ["bam", "cram"]},
                ],
            },
            {
                "key": "step01",
                "label": "Step 01 — Preprocess BAM",
                "run_key": "run_step01",
                "params": [
                    {"key": "nthreads",    "label": "samtools threads",          "type": "int",   "default": 4},
                    {"key": "short_lower", "label": "Short frag lower bound (bp)", "type": "int", "default": 50},
                    {"key": "short_upper", "label": "Short frag upper bound (bp)", "type": "int", "default": 150},
                    {"key": "long_lower",  "label": "Long frag lower bound (bp)",  "type": "int", "default": 151},
                    {"key": "long_upper",  "label": "Long frag upper bound (bp)",  "type": "int", "default": 350},
                    {"key": "min_flen",    "label": "Min fragment length (BEDPE)", "type": "int",  "default": 50},
                    {"key": "max_flen",    "label": "Max fragment length (BEDPE)", "type": "int",  "default": 350},
                    {"key": "markdup",     "label": "Mark duplicates (Picard)",    "type": "bool", "default": False},
                ],
            },
            {
                "key": "step02",
                "label": "Step 02 — Chromosome Features",
                "run_key": "run_step02",
                "params": [],
            },
            {
                "key": "step03",
                "label": "Step 03 — CNA Features",
                "run_key": "run_step03",
                "params": [],
            },
            {
                "key": "step04",
                "label": "Step 04 — Coverage Profile Features",
                "run_key": "run_step04",
                "params": [],
            },
            {
                "key": "step05",
                "label": "Step 05 — WPS / IFS / FDI Features",
                "run_key": "run_step05",
                "params": [],
            },
            {
                "key": "step06",
                "label": "Step 06 — RFE Features",
                "run_key": "run_step06",
                "params": [],
            },
            {
                "key": "resources",
                "label": "Resource Directory",
                "run_key": None,
                "params": [
                    {"key": "resource_dir", "label": "Resource directory (contains hg19.fa, rpr_map_EXP0779.bed, TFBS/)", "type": "str", "default": "/data/resources"},
                ],
            },
        ],
    },
    "fragmentomics_bulk_features": {
        "name": "Fragmentomics — Bulk Features",
        "description": "Computes bulk fragmentomics features from BAM files (mode `from_bam`) or pre-computed FLEN_EM_ND.tsv tables (mode `from_frag_file`).",
        "readme": "fragmentomics_bulk_features/README.md",
        "input_mode": "samplesheet",
        "input_files": [
            {"key": "samplesheet", "label": "samplesheet.csv  (SampleID, Path columns)"},
        ],
        "steps": [
            {
                "key": "options",
                "label": "Options",
                "run_key": None,
                "params": [
                    {"key": "mode",         "label": "Input mode",       "type": "select", "default": "from_bam", "options": ["from_bam", "from_frag_file"]},
                    {"key": "resource_dir", "label": "Resource directory (contains hg19.fa, rpr_map_Budhraja_STM2023.bed)", "type": "str", "default": "/data/resources"},
                    {"key": "min_flen",      "label": "Min fragment length",   "type": "int",    "default": 50},
                    {"key": "max_flen",      "label": "Max fragment length",   "type": "int",    "default": 350},
                    {"key": "outdir",        "label": "Output folder",         "type": "str",    "default": "results"},
                ],
            },
        ],
    },
    "fragmentomics_binwise_features": {
        "name": "Fragmentomics — Binwise Features",
        "description": "Computes per-bin read counts across short/long/full BAM files using an R script. Samplesheet must have columns SampleID, short_bam, long_bam, full_bam.",
        "readme": "fragmentomics_binwise_features/README.md",
        "input_mode": "samplesheet",
        "input_files": [
            {"key": "samplesheet", "label": "samplesheet.csv  (SampleID, short_bam, long_bam, full_bam columns)"},
        ],
        "steps": [
            {
                "key": "options",
                "label": "Options",
                "run_key": None,
                "params": [
                    {"key": "outdir",        "label": "Output folder",                                                          "type": "str", "default": "results"},
                    {"key": "split_cutoff",  "label": "Short/long split cutoff (bp, used when short_bam/long_bam not in samplesheet)", "type": "int", "default": 150},
                ],
            },
        ],
    },
    "fragmentomics_enrich_features": {
        "name": "Fragmentomics — Enrichment Filters",
        "description": "Filters BAM files or fragment tables by BED region, fragment lengths, or nucleosome distance. Choose a mode and supply the appropriate samplesheet.",
        "readme": "fragmentomics_enrich_features/README.md",
        "input_mode": "samplesheet",
        "input_files": [
            {"key": "samplesheet", "label": "samplesheet.csv"},
        ],
        "steps": [
            {
                "key": "options",
                "label": "Options",
                "run_key": None,
                "params": [
                    {"key": "mode",    "label": "Filter mode",  "type": "select", "default": "filter_flen",
                     "options": ["filter_flen", "filter_bed", "filter_nd"]},
                    {"key": "outdir",  "label": "Output folder", "type": "str",   "default": "results"},
                ],
            },
            {
                "key": "filter_bed_opts",
                "label": "BED filter options",
                "run_key": None,
                "params": [
                    {"key": "bed_file", "label": "BED file path (server-side)", "type": "str", "default": ""},
                ],
            },
            {
                "key": "filter_nd_opts",
                "label": "Nucleosome-distance filter options",
                "run_key": None,
                "params": [
                    {"key": "nd_min", "label": "ND min", "type": "int", "default": 0},
                    {"key": "nd_max", "label": "ND max", "type": "int", "default": 50},
                ],
            },
        ],
    },
    "bcr_immcantation_pipeline": {
        "name": "BCR Repertoire — Immcantation",
        "description": "Runs the Immcantation framework (IgBLAST, Change-O, SHazaM, Alakazam, dowser) on single-cell BCR data from 10x Genomics cellranger vdj: V(D)J reannotation, clonal clustering, germline reconstruction, somatic hypermutation, clonal diversity, gene usage, and optional lineage trees.",
        "readme": "bcr_immcantation_pipeline/README.md",
        "input_mode": "samplesheet",
        "input_files": [
            {"key": "samplesheet", "label": "samplesheet.csv  (SampleID, contig_fasta, contig_annotations, subject columns)"},
        ],
        "steps": [
            {
                "key": "s1",
                "label": "S1 — IgBLAST V(D)J Reannotation",
                "run_key": None,   # always runs
                "params": [
                    {"key": "species", "label": "Species", "type": "select", "default": "human", "options": ["human", "mouse"]},
                ],
            },
            {
                "key": "s3",
                "label": "S3 — Clonal Distance Threshold (SHazaM)",
                "run_key": None,
                "params": [
                    {"key": "auto_threshold", "label": "Auto-detect threshold (density method)", "type": "bool",  "default": True},
                    {"key": "dist_threshold", "label": "Manual/fallback threshold",               "type": "float", "default": 0.15},
                ],
            },
            {
                "key": "s4",
                "label": "S4 — Clonal Clustering (Change-O)",
                "run_key": None,
                "params": [
                    {"key": "clone_model", "label": "Distance model", "type": "select", "default": "ham", "options": ["ham", "aa", "hh_s1f", "hh_s5f"]},
                    {"key": "clone_norm",  "label": "Normalization",  "type": "select", "default": "len", "options": ["len", "none"]},
                ],
            },
            {
                "key": "s7",
                "label": "S7 — Clonal Abundance & Diversity (Alakazam)",
                "run_key": None,
                "params": [
                    {"key": "nboot", "label": "Diversity bootstrap replicates", "type": "int", "default": 100},
                ],
            },
            {
                "key": "s9",
                "label": "S9 — Lineage Trees (dowser)",
                "run_key": "run_lineage",
                "params": [
                    {"key": "lineage_min_seqs", "label": "Min sequences per clone to build a tree", "type": "int", "default": 3},
                ],
            },
            {
                "key": "s10",
                "label": "S10 — Render HTML Report",
                "run_key": "run_report",
                "params": [],
            },
        ],
    },
    "bcr_scirpy_pipeline": {
        "name": "BCR Repertoire — scirpy",
        "description": "Runs scirpy (scverse) on single-cell BCR data from 10x Genomics cellranger vdj: chain QC, clonotype definition, clonal expansion, diversity, repertoire overlap, and V/J gene usage/spectratype. Trusts Cell Ranger's own V(D)J gene calls (no IgBLAST reannotation).",
        "readme": "bcr_scirpy_pipeline/README.md",
        "input_mode": "samplesheet",
        "input_files": [
            {"key": "samplesheet", "label": "samplesheet.csv  (SampleID, contig_annotations, subject columns)"},
        ],
        "steps": [
            {
                "key": "s2",
                "label": "S2 — Chain QC & Filtering",
                "run_key": None,   # always runs
                "params": [
                    {"key": "remove_multichain", "label": "Remove multichain cells", "type": "bool", "default": True},
                    {"key": "require_paired",    "label": "Require a paired chain",  "type": "bool", "default": True},
                ],
            },
            {
                "key": "s3",
                "label": "S3 — Clonotype Definition",
                "run_key": None,
                "params": [
                    {"key": "clustering_mode", "label": "Clustering mode",        "type": "select", "default": "clonotype_clusters", "options": ["clonotypes", "clonotype_clusters"]},
                    {"key": "sequence",        "label": "Sequence (clusters only)", "type": "select", "default": "nt",     "options": ["nt", "aa"]},
                    {"key": "metric",          "label": "Distance metric (clusters only)", "type": "select", "default": "hamming", "options": ["identity", "hamming", "levenshtein", "alignment"]},
                    {"key": "receptor_arms",   "label": "Receptor arms",          "type": "select", "default": "all",     "options": ["all", "any", "VJ", "VDJ"]},
                    {"key": "dual_ir",         "label": "Dual IR handling",       "type": "select", "default": "primary_only", "options": ["primary_only", "any", "all"]},
                ],
            },
            {
                "key": "s5",
                "label": "S5 — Alpha Diversity",
                "run_key": None,
                "params": [
                    {"key": "diversity_metric", "label": "Diversity metric", "type": "select", "default": "normalized_shannon_entropy",
                     "options": ["normalized_shannon_entropy", "gini_simpson", "D50", "chao1"]},
                ],
            },
            {
                "key": "s6",
                "label": "S6 — Repertoire Overlap",
                "run_key": None,
                "params": [
                    {"key": "overlap_metric", "label": "Overlap metric", "type": "select", "default": "jaccard", "options": ["jaccard", "morisita_horn"]},
                ],
            },
            {
                "key": "s8",
                "label": "S8 — Render HTML Report",
                "run_key": "run_report",
                "params": [],
            },
        ],
    },
    "bcr_immunarch_pipeline": {
        "name": "BCR Repertoire — immunarch",
        "description": "Runs immunarch on single-cell BCR data from 10x Genomics cellranger vdj: repertoire exploration, clonality, diversity, V/J gene usage, optional clonal tracking and k-mer analysis, and pairwise repertoire overlap. The fastest/most exploratory of the four BCR pipelines; trusts Cell Ranger's own V(D)J gene calls.",
        "readme": "bcr_immunarch_pipeline/README.md",
        "input_mode": "samplesheet",
        "input_files": [
            {"key": "samplesheet", "label": "samplesheet.csv  (SampleID, contig_annotations, subject columns)"},
        ],
        "steps": [
            {
                "key": "s2",
                "label": "S2 — Repertoire Exploration",
                "run_key": None,   # always runs
                "params": [
                    {"key": "explore_method", "label": "Metric", "type": "select", "default": "volume", "options": ["volume", "len", "count", "samples"]},
                ],
            },
            {
                "key": "s3",
                "label": "S3 — Clonality",
                "run_key": None,
                "params": [
                    {"key": "clonality_method", "label": "Method", "type": "select", "default": "clonal.prop", "options": ["homeo", "clonal.prop", "top", "rare"]},
                ],
            },
            {
                "key": "s4",
                "label": "S4 — Diversity",
                "run_key": None,
                "params": [
                    {"key": "diversity_method", "label": "Method", "type": "select", "default": "chao1",
                     "options": ["chao1", "hill", "div", "gini.simp", "inv.simp", "gini", "raref"]},
                ],
            },
            {
                "key": "s5",
                "label": "S5 — V/J Gene Usage",
                "run_key": None,
                "params": [
                    {"key": "gene_reference", "label": "immunarch gene reference", "type": "select", "default": "hs.ighv",
                     "options": ["hs.ighv", "hs.igkv", "hs.iglv", "hs.ighj", "hs.igkj", "hs.iglj"]},
                    {"key": "gene_col", "label": "Fallback column (if reference unrecognized)", "type": "select", "default": "V.name", "options": ["V.name", "J.name"]},
                ],
            },
            {
                "key": "s6",
                "label": "S6 — Clonal Tracking",
                "run_key": "run_tracking",
                "params": [
                    {"key": "top_n_clonotypes", "label": "Top N clonotypes to track", "type": "int", "default": 10},
                ],
            },
            {
                "key": "s7",
                "label": "S7 — Repertoire Overlap",
                "run_key": None,
                "params": [
                    {"key": "overlap_method", "label": "Method", "type": "select", "default": "jaccard", "options": ["public", "jaccard", "morisita", "tversky", "cosine"]},
                ],
            },
            {
                "key": "s8",
                "label": "S8 — K-mer Analysis",
                "run_key": "run_kmer",
                "params": [
                    {"key": "kmer_k",    "label": "K-mer length",       "type": "int", "default": 5},
                    {"key": "kmer_head", "label": "Top K-mers to show", "type": "int", "default": 10},
                ],
            },
            {
                "key": "s9",
                "label": "S9 — Render HTML Report",
                "run_key": "run_report",
                "params": [],
            },
        ],
    },
    "bcr_dandelion_pipeline": {
        "name": "BCR Repertoire — Dandelion",
        "description": "Runs sc-dandelion on single-cell BCR data from 10x Genomics cellranger vdj: IgBLAST reannotation, contig QC, clone definition, and Dandelion's signature clonal similarity network, plus clone size, diversity, and V gene usage. Independently reannotates V(D)J genes via IgBLAST like Immcantation.",
        "readme": "bcr_dandelion_pipeline/README.md",
        "input_mode": "samplesheet",
        "input_files": [
            {"key": "samplesheet", "label": "samplesheet.csv  (SampleID, contig_fasta, contig_annotations, subject columns)"},
        ],
        "steps": [
            {
                "key": "s1",
                "label": "S1 — Format & IgBLAST Reannotation",
                "run_key": None,   # always runs
                "params": [
                    {"key": "species", "label": "Species", "type": "select", "default": "human", "options": ["human", "mouse"]},
                ],
            },
            {
                "key": "s2",
                "label": "S2 — Contig QC",
                "run_key": None,
                "params": [
                    {"key": "productive_only", "label": "Productive contigs only", "type": "bool", "default": True},
                ],
            },
            {
                "key": "s3",
                "label": "S3 — Clone Definition",
                "run_key": None,
                "params": [
                    {"key": "identity_threshold", "label": "CDR3 identity threshold", "type": "float", "default": 0.85},
                ],
            },
            {
                "key": "s4",
                "label": "S4 — Clonal Similarity Network",
                "run_key": None,
                "params": [
                    {"key": "min_network_size", "label": "Min clone size to include", "type": "int", "default": 2},
                ],
            },
            {
                "key": "s5",
                "label": "S5 — Clone Size & Diversity",
                "run_key": None,
                "params": [
                    {"key": "diversity_method", "label": "Diversity metric", "type": "select", "default": "chao1", "options": ["chao1", "shannon", "simpson", "gini"]},
                ],
            },
            {
                "key": "s7",
                "label": "S7 — Render HTML Report",
                "run_key": "run_report",
                "params": [],
            },
        ],
    },
    "basic_Seurat_single_cell_pipeline": {
        "name": "Seurat object from 10x CellRanger",
        "description": "Runs the full Seurat single-cell pipeline. Upload either a single CellRanger triplet (barcodes/features/matrix) or a samplesheet CSV (SampleID, barcodes, matrix, features) for multiple samples.",
        "readme": "basic_Seurat_single_cell_pipeline/README.md",
        "input_mode": "seurat",
        "input_files": [],
        # steps: ordered list of pipeline steps; each has a run_key (None = always runs)
        # and a list of params. The frontend renders one collapsible panel per step.
        "steps": [
            {
                "key": "s1",
                "label": "S1 — Create Seurat Object",
                "run_key": None,   # always runs
                "params": [
                    {"key": "outdir",           "label": "Output folder name",     "type": "str",   "default": "results"},
                    {"key": "min_cells",        "label": "Min cells per feature",  "type": "int",   "default": 3},
                    {"key": "min_features",     "label": "Min features per cell",  "type": "int",   "default": 200},
                    {"key": "max_features",     "label": "Max features per cell",  "type": "int",   "default": 5000},
                    {"key": "max_mt_pct",       "label": "Max % mitochondrial",    "type": "float", "default": 20},
                    {"key": "sample_name",      "label": "Sample name (single-sample mode only)", "type": "str", "default": "sample"},
                    {"key": "remove_TCR_genes", "label": "Remove TCR genes",       "type": "bool",  "default": False},
                ],
            },
            {
                "key": "s1b",
                "label": "S1b — Downsample Cells",
                "run_key": "run_downsample",
                "params": [
                    {"key": "downsample_type",  "label": "Method",
                     "type": "select", "default": "percent", "options": ["percent", "number"]},
                    {"key": "downsample_value", "label": "Value (% or cell count)",
                     "type": "float", "default": ""},
                ],
            },
            {
                "key": "s2",
                "label": "S2 — Ambient RNA Correction",
                "run_key": "run_s2",
                "params": [
                    {"key": "ambient_method", "label": "Method", "type": "select", "default": "decontX",
                     "options": ["decontX", "SoupX", "none"]},
                ],
            },
            {
                "key": "s3",
                "label": "S3 — Cell Filtering",
                "run_key": "run_s3",
                "params": [
                    {"key": "nFeatureRNA_floor",      "label": "nFeature floor",          "type": "float", "default": ""},
                    {"key": "nFeatureRNA_ceiling",    "label": "nFeature ceiling",         "type": "float", "default": ""},
                    {"key": "nCountRNA_floor",        "label": "nCount floor",             "type": "float", "default": ""},
                    {"key": "nCountRNA_ceiling",      "label": "nCount ceiling",           "type": "float", "default": ""},
                    {"key": "pct_mito_floor",         "label": "% mito floor",             "type": "float", "default": ""},
                    {"key": "pct_mito_ceiling",       "label": "% mito ceiling",           "type": "float", "default": ""},
                    {"key": "pct_ribo_floor",         "label": "% ribo floor",             "type": "float", "default": ""},
                    {"key": "pct_ribo_ceiling",       "label": "% ribo ceiling",           "type": "float", "default": ""},
                    {"key": "ambientRNA_thres",       "label": "AmbientRNA threshold",     "type": "float", "default": ""},
                    {"key": "log10GenesPerUMI_thres", "label": "log10GenesPerUMI ≥",       "type": "float", "default": ""},
                ],
            },
            {
                "key": "s4",
                "label": "S4 — Doublet Detection",
                "run_key": "run_s4",
                "params": [
                    {"key": "remove_doublet", "label": "Remove doublets", "type": "bool", "default": False},
                ],
            },
            {
                "key": "s5",
                "label": "S5 — CC Pre-processing",
                "run_key": "run_s5",
                "params": [
                    {"key": "use_sctransform", "label": "Use SCTransform",            "type": "bool", "default": False},
                    {"key": "vars_to_regress", "label": "Vars to regress (CSV list)", "type": "str",  "default": "percent.mt"},
                ],
            },
            {
                "key": "s6",
                "label": "S6 — Cell Cycle Scoring",
                "run_key": "run_s6",
                "params": [
                    {"key": "cc_scoring_mode", "label": "Gene ID mode", "type": "select", "default": "gene_name",
                     "options": ["gene_name", "ensembl"]},
                ],
            },
            {
                "key": "s7",
                "label": "S7 — Regress Out",
                "run_key": "run_s7",
                "params": [
                    {"key": "features_to_regressOut", "label": "Features to regress (CSV or leave blank)", "type": "str",    "default": ""},
                    {"key": "regressOut_mode",         "label": "Mode",                                    "type": "select", "default": "alternative",
                     "options": ["alternative", "normal"]},
                ],
            },
            {
                "key": "s8",
                "label": "S8 — UMAP + Clustering",
                "run_key": "run_s8",
                "params": [
                    {"key": "num_PCA",                   "label": "Number of PCs",                      "type": "int",   "default": 50},
                    {"key": "num_PC_used_in_UMAP",       "label": "PCs used in UMAP",                   "type": "int",   "default": 30},
                    {"key": "num_PC_used_in_Clustering", "label": "PCs used in clustering",             "type": "int",   "default": 30},
                    {"key": "cluster_resolution",        "label": "Cluster resolution",                 "type": "float", "default": 0.5},
                    {"key": "s8_vars_to_regress",        "label": "Vars to regress in s8 (CSV)",        "type": "str",   "default": "percent.mt"},
                    {"key": "s8_remove_genes",           "label": "Genes to exclude from PCA (CSV)",    "type": "str",   "default": ""},
                ],
            },
            {
                "key": "s8a",
                "label": "S8a — Render HTML Report",
                "run_key": "run_s8a",
                "params": [],
            },
        ],
    },
    "single_cell_data_analysis_with_python": {
        "name": "Single Cell Data Analysis with Python",
        "description": "Python/scanpy port of the Seurat single-cell pipeline — same steps and parameters, "
                        "Scrublet/harmonypy/Scanorama/BBKNN in place of DoubletFinder/Harmony/CCA/RPCA. "
                        "Upload either a single CellRanger triplet (barcodes/features/matrix) or a "
                        "samplesheet CSV (SampleID, barcodes, matrix, features) for multiple samples.",
        "readme": "single_cell_data_analysis_with_python/README.md",
        "input_mode": "seurat",
        "input_files": [],
        "steps": [
            {
                "key": "s1",
                "label": "S1 — Create AnnData Object",
                "run_key": None,   # always runs
                "params": [
                    {"key": "outdir",           "label": "Output folder name",     "type": "str",   "default": "results"},
                    {"key": "min_cells",        "label": "Min cells per feature",  "type": "int",   "default": 3},
                    {"key": "min_features",     "label": "Min features per cell",  "type": "int",   "default": 200},
                    {"key": "max_features",     "label": "Max features per cell",  "type": "int",   "default": 5000},
                    {"key": "max_mt_pct",       "label": "Max % mitochondrial",    "type": "float", "default": 20},
                    {"key": "sample_name",      "label": "Sample name (single-sample mode only)", "type": "str", "default": "sample"},
                    {"key": "remove_TCR_genes", "label": "Remove TCR genes",       "type": "bool",  "default": False},
                ],
            },
            {
                "key": "s1b",
                "label": "S1b — Downsample Cells",
                "run_key": "run_downsample",
                "params": [
                    {"key": "downsample_type",  "label": "Method",
                     "type": "select", "default": "percent", "options": ["percent", "number"]},
                    {"key": "downsample_value", "label": "Value (% or cell count)",
                     "type": "float", "default": ""},
                ],
            },
            {
                "key": "s2",
                "label": "S2 — Ambient RNA Correction",
                "run_key": "run_s2",
                "params": [
                    {"key": "ambient_method", "label": "Method", "type": "select", "default": "decontX",
                     "options": ["decontX", "SoupX", "none"]},
                ],
            },
            {
                "key": "s3",
                "label": "S3 — Cell Filtering",
                "run_key": "run_s3",
                "params": [
                    {"key": "nFeatureRNA_floor",      "label": "nFeature floor",          "type": "float", "default": ""},
                    {"key": "nFeatureRNA_ceiling",    "label": "nFeature ceiling",         "type": "float", "default": ""},
                    {"key": "nCountRNA_floor",        "label": "nCount floor",             "type": "float", "default": ""},
                    {"key": "nCountRNA_ceiling",      "label": "nCount ceiling",           "type": "float", "default": ""},
                    {"key": "pct_mito_floor",         "label": "% mito floor",             "type": "float", "default": ""},
                    {"key": "pct_mito_ceiling",       "label": "% mito ceiling",           "type": "float", "default": ""},
                    {"key": "pct_ribo_floor",         "label": "% ribo floor",             "type": "float", "default": ""},
                    {"key": "pct_ribo_ceiling",       "label": "% ribo ceiling",           "type": "float", "default": ""},
                    {"key": "ambientRNA_thres",       "label": "AmbientRNA threshold",     "type": "float", "default": ""},
                    {"key": "log10GenesPerUMI_thres", "label": "log10GenesPerUMI ≥",       "type": "float", "default": ""},
                ],
            },
            {
                "key": "s4",
                "label": "S4 — Doublet Detection",
                "run_key": "run_s4",
                "params": [
                    {"key": "remove_doublet", "label": "Remove doublets", "type": "bool", "default": False},
                ],
            },
            {
                "key": "s5",
                "label": "S5 — CC Pre-processing",
                "run_key": "run_s5",
                "params": [
                    {"key": "use_sctransform", "label": "Use Pearson-residual normalisation (SCTransform-equivalent)", "type": "bool", "default": False},
                    {"key": "vars_to_regress", "label": "Vars to regress (CSV list)", "type": "str",  "default": "percent.mt"},
                ],
            },
            {
                "key": "s6",
                "label": "S6 — Cell Cycle Scoring",
                "run_key": "run_s6",
                "params": [
                    {"key": "cc_scoring_mode", "label": "Gene ID mode", "type": "select", "default": "gene_name",
                     "options": ["gene_name", "ensembl"]},
                ],
            },
            {
                "key": "s7",
                "label": "S7 — Regress Out",
                "run_key": "run_s7",
                "params": [
                    {"key": "features_to_regressOut", "label": "Features to regress (CSV or leave blank)", "type": "str",    "default": ""},
                    {"key": "regressOut_mode",         "label": "Mode",                                    "type": "select", "default": "alternative",
                     "options": ["alternative", "normal"]},
                ],
            },
            {
                "key": "s8",
                "label": "S8 — UMAP + Clustering",
                "run_key": "run_s8",
                "params": [
                    {"key": "num_PCA",                   "label": "Number of PCs",                      "type": "int",   "default": 50},
                    {"key": "num_PC_used_in_UMAP",       "label": "PCs used in UMAP",                   "type": "int",   "default": 30},
                    {"key": "num_PC_used_in_Clustering", "label": "PCs used in clustering",             "type": "int",   "default": 30},
                    {"key": "cluster_resolution",        "label": "Cluster resolution",                 "type": "float", "default": 0.5},
                    {"key": "s8_vars_to_regress",        "label": "Vars to regress in s8 (CSV)",        "type": "str",   "default": "percent.mt"},
                    {"key": "s8_remove_genes",           "label": "Genes to exclude from PCA (CSV)",    "type": "str",   "default": ""},
                ],
            },
            {
                "key": "s8a",
                "label": "S8a — Render HTML Report",
                "run_key": "run_s8a",
                "params": [],
            },
        ],
    },
}


@router.get("/")
async def list_pipelines():
    return [{"id": k, **v} for k, v in PIPELINE_REGISTRY.items()]


PIPELINE_ALIASES = {
    "seurat_from_10x": "basic_Seurat_single_cell_pipeline",
}

@router.get("/{pipeline_id}/readme", response_class=PlainTextResponse)
async def get_pipeline_readme(pipeline_id: str):
    resolved = PIPELINE_ALIASES.get(pipeline_id, pipeline_id)
    entry = PIPELINE_REGISTRY.get(resolved)
    if not entry:
        raise HTTPException(404, "Pipeline not found")
    rel = entry.get("readme")
    if not rel:
        return PlainTextResponse("No description available.")
    path = os.path.join(PIPELINES_BASE, rel)
    if not os.path.exists(path):
        return PlainTextResponse("Description file not found.")
    return PlainTextResponse(open(path).read())


@router.get("/{pipeline_id}")
async def get_pipeline(pipeline_id: str):
    resolved = PIPELINE_ALIASES.get(pipeline_id, pipeline_id)
    if resolved not in PIPELINE_REGISTRY:
        raise HTTPException(404, "Pipeline not found")
    return {"id": resolved, **PIPELINE_REGISTRY[resolved]}
