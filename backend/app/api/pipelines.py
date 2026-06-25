"""Static registry of available pipelines."""
from fastapi import APIRouter

router = APIRouter(prefix="/pipelines", tags=["pipelines"])

PIPELINE_REGISTRY = {
    "seurat_from_10x": {
        "name": "Seurat object from 10x CellRanger",
        "description": "Creates a Seurat object from the barcodes/features/matrix triplet produced by CellRanger. Outputs an RDS file and QC plots.",
        "input_files": [
            {"key": "barcodes", "label": "barcodes.tsv.gz"},
            {"key": "features", "label": "features.tsv.gz"},
            {"key": "matrix",   "label": "matrix.mtx.gz"},
        ],
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
                    {"key": "sample_name",      "label": "Sample name",            "type": "str",   "default": "sample"},
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
        ],
    },
}


@router.get("/")
async def list_pipelines():
    return [{"id": k, **v} for k, v in PIPELINE_REGISTRY.items()]


@router.get("/{pipeline_id}")
async def get_pipeline(pipeline_id: str):
    if pipeline_id not in PIPELINE_REGISTRY:
        from fastapi import HTTPException
        raise HTTPException(404, "Pipeline not found")
    return {"id": pipeline_id, **PIPELINE_REGISTRY[pipeline_id]}
