import pandas as pd
import os
import numpy as np
import pysam
from tqdm import tqdm
import argparse
from collections import defaultdict
from bx.intervals.intersection import Intersecter, Interval
import warnings
warnings.filterwarnings("ignore")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--input', type=str, required=True)
    parser.add_argument('--output', type=str, required=True)
    parser.add_argument('--inputbed', type=str, required=True)
    parser.add_argument('--cna', type=str, required=True)
    parser.add_argument('--cov', type=str, required=True)
    parser.add_argument('--mapq', type=int, default=30, required=False)
    parser.add_argument('--expand_size', type=int, default=1000, required=False)
    parser.add_argument('--count_mode', type=str, required=True)
    parser.add_argument('--min_flen', type=int, default=50, required=False)
    parser.add_argument('--max_flen', type=int, default=350, required=False)
    parser.add_argument('--sampleid', type=str, required=True)

    args = parser.parse_args()
    inputfile = args.input
    outputdir = args.output
    inputbed = str(args.inputbed)
    inputcna = args.cna
    covfile = args.cov
    mapq = args.mapq
    min_flen = args.min_flen
    max_flen = args.max_flen
    expand_size = args.expand_size
    count_mode = args.count_mode
    sampleid = args.sampleid

    os.makedirs(outputdir, exist_ok=True)

    tfbsdir = outputdir
    tf = inputbed.split("/")[-1].replace(".bed", "")
    outfile = os.path.join(tfbsdir, f"{sampleid}_{tf}.tsv")

    if os.path.isfile(outfile):
        print(f"Result for TF {tf} exists")
        return

    os.makedirs(tfbsdir, exist_ok=True)

    covdf = pd.read_csv(covfile, sep="\t", header=None)
    mean_coverage = covdf[covdf[0] == "genome"][1].values[0]

    beddf = pd.read_csv(inputbed, sep="\t", header=None)
    beddf.columns = ["chrom", "start", "end", "v3", "v4", "v5"]

    # Load CNA once and build an interval tree per chrom for O(log n) lookup
    cnadf = pd.read_csv(inputcna, sep="\t", header=None)
    cnadf.columns = ["chrom", "start", "end", "log2.ratio"]
    cnadf = cnadf[cnadf["log2.ratio"].notna()]
    cna_trees = {}
    for chrom, grp in cnadf.groupby("chrom"):
        tree = Intersecter()
        for _, row in grp.iterrows():
            tree.add_interval(Interval(int(row["start"]), int(row["end"]), value=row["log2.ratio"]))
        cna_trees[chrom] = tree

    window = 2 * expand_size + 2  # length of keyrange: -expand_size-1 .. expand_size
    agg_normCov = np.zeros((window, beddf.shape[0]), dtype=np.float64)
    agg_rawCov = np.zeros((window, beddf.shape[0]), dtype=np.float64)

    # Open file handles once outside the loop
    if count_mode == "read":
        bamfile = pysam.AlignmentFile(inputfile, 'rb')
    elif count_mode == "fragment":
        tbx = pysam.TabixFile(inputfile)

    for tfbs_i, row in enumerate(tqdm(beddf.itertuples(index=False), total=beddf.shape[0])):
        region_chrom = row.chrom
        region_start = row.start
        region_end = row.end

        pos = int(np.floor(region_start + 0.5 * (region_end - region_start)))

        if count_mode == "read":
            c = bamfile.count_coverage(region_chrom, region_start, region_end + 1,
                                       quality_threshold=mapq)
            n = region_end - region_start + 1
            coverage = np.zeros(n, dtype=np.int32)
            for base in c:
                coverage += np.array(base[:n], dtype=np.int32)

        elif count_mode == "fragment":
            posRange = defaultdict(int)
            for tbx_row in tbx.fetch(region_chrom, region_start, region_end + 1):
                tmp = tbx_row.split()
                rstart = int(tmp[1]) + 1
                rend = int(tmp[2])
                flen = int(tmp[4])
                if min_flen <= flen <= max_flen:
                    lo = max(rstart, region_start)
                    hi = min(rend, region_end)
                    for i in range(lo, hi + 1):
                        posRange[i] += 1
            coverage = np.array(
                [posRange.get(i, 0) for i in range(region_start, region_end + 1)],
                dtype=np.int32
            )

        # CNA lookup via interval tree
        if region_chrom in cna_trees:
            hits = cna_trees[region_chrom].find(pos, pos + 1)
            normcov = float(np.power(2, hits[0].value)) if len(hits) == 1 else 1.0
        else:
            normcov = 1.0

        norm_coverage = (coverage.astype(np.float64) / mean_coverage) / normcov

        n = len(coverage)
        agg_normCov[:n, tfbs_i] = norm_coverage
        agg_rawCov[:n, tfbs_i] = coverage

    if count_mode == "read":
        bamfile.close()
    elif count_mode == "fragment":
        tbx.close()

    avg_normCov = np.mean(agg_normCov, axis=1)
    avg_rawCov = np.mean(agg_rawCov, axis=1)
    num_tfbs = np.count_nonzero(agg_normCov, axis=1)

    positions = np.arange(-expand_size - 1, expand_size + 1)
    mask = (positions >= -expand_size) & (positions <= expand_size)

    outputdf = pd.DataFrame({
        "Position": positions[mask],
        "Mean.Cov": avg_normCov[mask],
        "Raw.Cov": avg_rawCov[mask],
        "num_TFBS": num_tfbs[mask],
    })
    outputdf.to_csv(outfile, sep="\t", index=False)


if __name__ == '__main__':
    main()
