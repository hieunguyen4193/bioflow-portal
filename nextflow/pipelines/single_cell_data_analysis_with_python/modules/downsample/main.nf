process DOWNSAMPLE {
    tag "${sample}"
    publishDir "${params.outdir}/s1b_downsample", mode: "copy"

    input:
    tuple val(sample), path(h5ad)
    val  downsample_type    // "percent" | "number"
    val  downsample_value   // numeric: percent (0-100) or cell count

    output:
    tuple val(sample), path("${sample}_s1b.h5ad"), emit: anndata

    script:
    """
    cat > run_downsample.py << 'PYEOF'
import argparse
import scanpy as sc

p = argparse.ArgumentParser()
p.add_argument("--h5ad",   type=str)
p.add_argument("--sample", type=str, default="sample")
p.add_argument("--type",   type=str, default="percent")
p.add_argument("--value",  type=float, default=100)
opt = p.parse_args()

adata = sc.read_h5ad(opt.h5ad)
n_before = adata.n_obs

if opt.type == "percent":
    if opt.value <= 0 or opt.value >= 100:
        print(f"Downsampling percent must be between 0 and 100, got {opt.value} — skipping.")
    else:
        sc.pp.subsample(adata, fraction=opt.value / 100, random_state=42)
        print(f"Downsampled to {opt.value:.0f}% — {n_before} -> {adata.n_obs} cells")
elif opt.type == "number":
    n_keep = min(int(opt.value), n_before)
    sc.pp.subsample(adata, n_obs=n_keep, random_state=42)
    print(f"Downsampled to {n_keep} cells — {n_before} -> {adata.n_obs} cells")
else:
    print(f"Unknown downsample type '{opt.type}' — skipping.")

adata.write_h5ad(f"{opt.sample}_s1b.h5ad")
print("Downsampling done.")
PYEOF

    python3 run_downsample.py \\
        --h5ad   "${h5ad}" \\
        --sample "${sample}" \\
        --type   "${downsample_type ?: 'percent'}" \\
        --value  "${downsample_value ?: 100}"
    """
}
