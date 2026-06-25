import pandas as pd
import numpy as np
import os
import pysam
import pyfaidx
from collections import defaultdict
from bx.intervals.intersection import Intersecter, Interval
from tqdm import tqdm
import argparse
import pickle


def main():
    """
    Compute fragment length and 4bp end-motif features plus RFE metrics for regions in a BED file.

    Reads an indexed, gzip-compressed fragment BED and a target-region BED, then:
    - Builds per-position fragment-length distributions (FLD).
    - Builds per-position 4bp end-motif distributions (motif at fragment start).
    - Computes Shannon entropy and KL divergence versus genome-wide background for both FLD and motifs.

    Command-line Arguments:
        --input (str, required): Tabix-indexed fragment BED (.bed.gz). Columns:
            chrom, start, end, ..., flen (fragment length in 5th column).
        --output (str, required): Output directory for results.
        --inputbed (str, required): Target regions BED (TFBS/TSS). Columns: chrom, start, end, v3, v4, v5.
        --min_flen (int, required): Minimum fragment length to include.
        --max_flen (int, required): Maximum fragment length to include.
        --fa (str, required): Path to the reference genome FASTA file (e.g., hg19.fa).
        --sampleid (str, required): Sample identifier used in output file names.
        --fld (flag): If set, enables computation and saving of FLD features.
        --rfe (flag): If set, enables computation and saving of RFE (entropy/KL) features.
        --save_pkl (flag): If set, saves the combineRange pickle file.
        --save_fld (flag): If set, saves the 2D FLD and motif frequency TSV files (requires --fld).

    Output Files (per sample/bed):
        - {sampleid}_{bedname}.tsv: FLD table, columns [flen, position_<offset>, ...] with frequencies.
          Written only when both --fld and --save_fld are set.
        - {sampleid}_{bedname}.4bpMotif.tsv: 4bp motif frequency table per position.
          Written only when both --fld and --save_fld are set.
        - RFE_{sampleid}_{bedname}.tsv: FLD entropy and KL divergence per position.
          Written only when --rfe is set.
        - RFE_{sampleid}_{bedname}.4bpMotif.tsv: Motif entropy and KL divergence per position.
          Written only when --rfe is set.
        - RFE_combineRange_{sampleid}_{bedname}.pickle: dict mapping position offsets to
          "flen_motif" strings. Written only when --save_pkl is set.

    Notes:
        - Positions are stored as offsets relative to region_start with a -1000 shift.
        - Motifs are fetched from the reference FASTA at fragment start (1-based, 4bp window).
        - Background distributions are accumulated genome-wide across all queried regions.
        - Entropy is normalised by log2(n_bins) so values lie in [0, 1].
    """
    parser = argparse.ArgumentParser()
    parser.add_argument('--input', type=str, required=True,
                        help='Path to the input BED file containing DNA fragments')
    parser.add_argument('--output', type=str, required=True,
                        help='Path to save output')
    parser.add_argument('--inputbed', type=str, required=True,
                        help='Path to the input BED file containing targeted regions')
    parser.add_argument('--min_flen', type=int, required=True,
                        help='Minimum fragment length')
    parser.add_argument('--max_flen', type=int, required=True,
                        help='Maximum fragment length')
    parser.add_argument('--fld', action='store_true',
                        help='Save the FLD features')
    parser.add_argument('--rfe', action='store_true',
                        help='Save the RFE features')
    parser.add_argument('--save_pkl', action='store_true',
                        help='Save the pickle file features')
    parser.add_argument('--save_fld', action='store_true',
                        help='Save the FLD 2D features file')
    parser.add_argument('--fa', type=str, required=True,
                        help='Path to the reference genome FASTA file (e.g., hg19.fa)')
    parser.add_argument('--sampleid', type=str, required=True,
                        help='Sample ID')

    args = parser.parse_args()
    inputBedfile = args.input
    outputdir = args.output
    inputbed = args.inputbed
    min_flen = args.min_flen
    max_flen = args.max_flen
    fld = args.fld
    rfe = args.rfe
    path_to_fa = args.fa
    sampleid = args.sampleid
    save_pkl = args.save_pkl
    save_fld = args.save_fld

    bedname = str(inputbed).split("/")[-1].replace(".bed", "")
    beddf = pd.read_csv(inputbed, sep="\t", header=None)
    beddf.columns = ["chrom", "start", "end", "v3", "v4", "v5"]

    # Pre-build flen and motif index lookups
    flen_values = np.arange(min_flen, max_flen + 1)
    n_flen = len(flen_values)
    flen_idx = {int(f): i for i, f in enumerate(flen_values)}

    all_motifs_list = [f"{a}{b}{c}{d}" for a in "ATGC" for b in "ATGC" for c in "ATGC" for d in "ATGC"]
    n_motifs = len(all_motifs_list)  # 256
    motif_idx = {m: i for i, m in enumerate(all_motifs_list)}

    # Per-position count arrays (offset -> numpy array)
    flenRange = defaultdict(lambda: np.zeros(n_flen, dtype=np.int32))
    motifRange = defaultdict(lambda: np.zeros(n_motifs, dtype=np.int32))

    # Background counts accumulated across all positions
    all_flen_counts = np.zeros(n_flen, dtype=np.int64)
    all_motif_counts = np.zeros(n_motifs, dtype=np.int64)

    # combineRange is only needed for pkl output
    combineRange = defaultdict(list) if save_pkl else None

    fa = pyfaidx.Fasta(path_to_fa, as_raw=True, sequence_always_upper=True)
    tbx = pysam.TabixFile(inputBedfile)  # open once for all regions

    for _, row in tqdm(beddf.iterrows(), total=len(beddf)):
        region_chrom = row["chrom"]
        region_start = int(row["start"])
        region_end = int(row["end"])
        region_size = region_end - region_start

        # Per-region 2D accumulator blocks; slice-assignment replaces per-position Python loop
        flen_block = np.zeros((region_size, n_flen), dtype=np.int32)
        motif_block = np.zeros((region_size, n_motifs), dtype=np.int32)

        for line in tbx.fetch(region_chrom, region_start, region_end):
            tmp_row = line.split()
            rstart = int(tmp_row[1]) + 1  # convert to 1-based
            rend = int(tmp_row[2])
            flen = int(tmp_row[4])

            fi = flen_idx.get(flen)
            if fi is None:
                continue

            motif = fa[region_chrom][rstart - 1: rstart + 3]
            if len(motif) != 4:
                continue
            mi = motif_idx.get(motif)

            overlap_start = max(rstart, region_start)
            overlap_end = min(rend, region_end)
            if overlap_start > overlap_end:
                continue

            start_idx = overlap_start - region_start
            end_idx = overlap_end - region_start + 1  # exclusive

            # Single numpy slice op replaces `for i in range(overlap_start, overlap_end+1)`
            flen_block[start_idx:end_idx, fi] += 1
            if mi is not None:
                motif_block[start_idx:end_idx, mi] += 1

            if combineRange is not None:
                for pos_idx in range(start_idx, end_idx):
                    combineRange[pos_idx - 1000].append(f"{flen}_{motif}")

        # Accumulate block into global per-offset dicts and background counts
        all_flen_counts += flen_block.sum(axis=0)
        all_motif_counts += motif_block.sum(axis=0)

        for pos_idx in range(region_size):
            if flen_block[pos_idx].any() or motif_block[pos_idx].any():
                offset = pos_idx - 1000
                flenRange[offset] += flen_block[pos_idx]
                motifRange[offset] += motif_block[pos_idx]

    tbx.close()

    # Build DataFrames from pre-computed count arrays (O(n) vs original O(n²) merge loop)
    positions = sorted(flenRange.keys())
    n_pos = len(positions)

    if fld or rfe:
        flen_matrix = np.zeros((n_flen, n_pos), dtype=np.float64)
        motif_matrix = np.zeros((n_motifs, n_pos), dtype=np.float64)
        for j, pos in enumerate(positions):
            col_f = flenRange[pos].astype(np.float64)
            total_f = col_f.sum()
            if total_f > 0:
                flen_matrix[:, j] = col_f / total_f

            col_m = motifRange[pos].astype(np.float64)
            total_m = col_m.sum()
            if total_m > 0:
                motif_matrix[:, j] = col_m / total_m

        pos_col_names = [f"position_{p}" for p in positions]

        flendf = pd.DataFrame(flen_matrix, index=flen_values, columns=pos_col_names)
        flendf.index.name = "flen"
        flendf = flendf.reset_index()

        motifdf = pd.DataFrame(motif_matrix, index=all_motifs_list, columns=pos_col_names)
        motifdf.index.name = "motif"
        motifdf = motifdf.reset_index()

        if fld and save_fld:
            flendf.to_csv(os.path.join(outputdir, f"{sampleid}_{bedname}.tsv"), sep="\t", index=False)
            motifdf.to_csv(os.path.join(outputdir, f"{sampleid}_{bedname}.4bpMotif.tsv"), sep="\t", index=False)

    def kl_divergence(a, b, epsilon=1e-6):
        """
        Compute KL divergence D_KL(a || b) with zero-probability smoothing.

        Args:
            a (np.ndarray): Probability distribution P (query). Zero entries are replaced by epsilon.
            b (np.ndarray): Probability distribution Q (reference). Zero entries are replaced by epsilon.
            epsilon (float): Small constant substituted for zero probabilities to avoid log(0).

        Returns:
            float: KL divergence sum(a * log(a / b)).
        """
        a = np.where(a == 0, epsilon, a)
        b = np.where(b == 0, epsilon, b)
        return float(np.sum(a * np.log(a / b)))

    if rfe:
        # Background frequency vectors
        bg_flen = all_flen_counts.astype(np.float64)
        bg_flen_total = bg_flen.sum()
        if bg_flen_total > 0:
            bg_flen /= bg_flen_total

        bg_motif = all_motif_counts.astype(np.float64)
        bg_motif_total = bg_motif.sum()
        if bg_motif_total > 0:
            bg_motif /= bg_motif_total

        # Vectorized entropy and KL over all positions at once
        flen_pos_matrix = flen_matrix  # shape (n_flen, n_pos)
        with np.errstate(divide='ignore', invalid='ignore'):
            log2_flen = np.where(flen_pos_matrix > 0, np.log2(flen_pos_matrix), 0.0)
        flen_entropy = -np.sum(flen_pos_matrix * log2_flen, axis=0) / np.log2(n_flen)

        flen_a = np.where(flen_pos_matrix == 0, 1e-6, flen_pos_matrix)  # (n_flen, n_pos)
        flen_b = np.where(bg_flen[:, None] == 0, 1e-6, bg_flen[:, None])
        flen_kl = np.sum(flen_a * np.log(flen_a / flen_b), axis=0)

        entropydf_flen = pd.DataFrame({
            "position": pos_col_names,
            "entropy": flen_entropy,
            "KLdiv": flen_kl,
        })
        entropydf_flen.to_csv(os.path.join(outputdir, f"RFE_{sampleid}_{bedname}.tsv"), sep="\t", index=False)

        motif_pos_matrix = motif_matrix  # shape (n_motifs, n_pos)
        with np.errstate(divide='ignore', invalid='ignore'):
            log2_motif = np.where(motif_pos_matrix > 0, np.log2(motif_pos_matrix), 0.0)
        motif_entropy = -np.sum(motif_pos_matrix * log2_motif, axis=0) / np.log2(n_motifs)

        motif_a = np.where(motif_pos_matrix == 0, 1e-6, motif_pos_matrix)
        motif_b = np.where(bg_motif[:, None] == 0, 1e-6, bg_motif[:, None])
        motif_kl = np.sum(motif_a * np.log(motif_a / motif_b), axis=0)

        entropydf_motif = pd.DataFrame({
            "position": pos_col_names,
            "entropy": motif_entropy,
            "KLdiv": motif_kl,
        })
        entropydf_motif.to_csv(os.path.join(outputdir, f"RFE_{sampleid}_{bedname}.4bpMotif.tsv"), sep="\t", index=False)

    if save_pkl:
        with open(os.path.join(outputdir, f'RFE_combineRange_{sampleid}_{bedname}.pickle'), 'wb') as handle:
            pickle.dump(dict(combineRange), handle, protocol=pickle.HIGHEST_PROTOCOL)


if __name__ == '__main__':
    main()


# ***** test this function *****
# example cmd in 12_generate_RFE_features_with_enhanced_script.sh
# EOF