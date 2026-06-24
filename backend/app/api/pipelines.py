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
        "params": [
            {"key": "min_cells",    "label": "Min cells per feature",  "type": "int",   "default": 3},
            {"key": "min_features", "label": "Min features per cell",  "type": "int",   "default": 200},
            {"key": "max_features", "label": "Max features per cell",  "type": "int",   "default": 5000},
            {"key": "max_mt_pct",   "label": "Max % mitochondrial",    "type": "float", "default": 20},
            {"key": "sample_name",  "label": "Sample name",            "type": "str",   "default": "sample"},
            {"key": "remove_TCR_genes", "label": "Reomove TCR genes",  "type": "bool",   "default": False}  
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
