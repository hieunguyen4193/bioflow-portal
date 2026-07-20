process REGRESS_OUT {
    tag "${sample}"
    publishDir "${params.outdir}/s7_regress_out",               mode: "copy"

    input:
    tuple val(sample), path(h5ad)
    val  features_to_regressOut
    val  regressOut_mode

    output:
    tuple val(sample), path("${sample}_s7.h5ad"), emit: anndata

    script:
    """
    cat > run_s7.py << 'PYEOF'
import argparse

import scanpy as sc

sc.settings.verbosity = 1

p = argparse.ArgumentParser()
p.add_argument("--h5ad",                    type=str)
p.add_argument("--sample",                  type=str, default="sample")
p.add_argument("--features_to_regressOut",  type=str, default="none")
p.add_argument("--regressOut_mode",         type=str, default="alternative")
opt = p.parse_args()

adata = sc.read_h5ad(opt.h5ad)


def s7_cell_factor_regress_out(adata, features_to_regress_out, regress_out_mode):
    if features_to_regress_out and features_to_regress_out != "none":
        adata.obs["CC_difference"] = adata.obs["S_score"] - adata.obs["G2M_score"]

        if regress_out_mode == "normal":
            vars_ = [v.strip().replace(".", "_") for v in features_to_regress_out.split(",")]
            print("Regressing out (normal):", ", ".join(vars_))
            sc.pp.regress_out(adata, keys=vars_)
        elif regress_out_mode == "alternative":
            print("Regressing out CC_difference (alternative)")
            sc.pp.regress_out(adata, keys=["CC_difference"])
        else:
            raise ValueError(f"regressOut_mode must be 'normal' or 'alternative'. Got: {regress_out_mode}")
    else:
        print("features_to_regressOut is none — skipping regress-out.")
    return adata


adata = s7_cell_factor_regress_out(
    adata,
    features_to_regress_out=opt.features_to_regressOut,
    regress_out_mode=opt.regressOut_mode,
)

adata.write_h5ad(f"{opt.sample}_s7.h5ad")
print("Step 7 complete.")
PYEOF

    python3 run_s7.py \\
        --h5ad                   "${h5ad}" \\
        --sample                 "${sample}" \\
        --features_to_regressOut "${features_to_regressOut}" \\
        --regressOut_mode        "${regressOut_mode}"
    """
}
