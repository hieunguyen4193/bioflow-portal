import pandas as pd 
import numpy as np 
import pathlib
import os
import pysam
import pyfaidx
import pybedtools
from collections import defaultdict
from bx.intervals.intersection import Intersecter, Interval
import matplotlib.pyplot as plt
from tqdm import tqdm
from collections import Counter
import seaborn as sns
import argparse
import sys 
import pickle

# input args
# inputBedfile = "/Users/hieunguyen/outdir/ecd_wgs_and_enriched_features/ABC123.sorted_region_Full_fraglen_50_350.sorted.bed.gz"
# outputdir = "/Users/hieunguyen/outdir/ecd_wgs_and_enriched_features"
# beddir = "/Users/hieunguyen/src/ecd_wgs_and_enriched_features/preprocessed_resources/TFBS"
# inputbed = "/Users/hieunguyen/src/ecd_wgs_and_enriched_features/preprocessed_resources/TFBS/Mad3.Top1000sites_1000.hg19.bed"
# min_flen = 50
# max_flen = 350
# fld = True
# rfe = True

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

    Output Files (per sample/bed):
        - {sampleid}_{bedname}.tsv: FLD table, columns [flen, position_<offset>, ...] with frequencies.
        - {sampleid}_{bedname}.4bpMotif.tsv: 4bp motif frequency table per position.
        - RFE_{sampleid}_{bedname}.tsv: FLD entropy and KL divergence per position.
        - RFE_{sampleid}_{bedname}.4bpMotif.tsv: Motif entropy and KL divergence per position.
        - combineRange_{sampleid}.pickle: dict mapping position offsets to flen_motif pairs.

    Notes:
        - Positions are stored as offsets relative to region_start with a -1000 shift.
        - Motifs are fetched from hg19 reference at fragment start (1-based).
    """
    parser = argparse.ArgumentParser()
    parser.add_argument('--input', 
                        type = str, 
                        required = True, 
                        help = 'Path to the input BED file containing DNA fragments')
    parser.add_argument('--output', 
                        type = str, 
                        required = True, 
                        help = 'Path to save output')
    parser.add_argument('--inputbed', 
                        type = str, 
                        required = True, 
                        help = 'Path to the input BED file containing targeted regions')
    parser.add_argument('--min_flen', 
                        type = int, 
                        required = True, 
                        help = 'Minimum fragment length')
    parser.add_argument('--max_flen', 
                        type = int, 
                        required = True, 
                        help = 'Maximum fragment length')
    parser.add_argument('--fld', 
                    action='store_true', 
                    help='Save the FLD features')
    parser.add_argument('--rfe', 
                    action='store_true', 
                    help='Save the RFE features')
    parser.add_argument('--save_pkl', 
                    action='store_true', 
                    help='Save the pickle file features')
    parser.add_argument('--save_fld', 
                    action='store_true', 
                    help='Save the FLD 2D features file')
    parser.add_argument('--fa',
                        type = str, 
                        required = True, 
                        help = 'Path to the reference genome FASTA file (e.g., hg19.fa)')
    parser.add_argument('--sampleid',
                    type = str, 
                    required = True, 
                    help = 'Sample ID')

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
    # hardcode these input args, always generate the FLD feature and the RFE score. 
    # fld = True
    # rfe = True
    
    # hardcode these input args, always generate the FLD feature and the RFE score. 
    bedname = str(inputbed).split("/")[-1].replace(".bed", "")
    
    # this can be TSS or TFBS bed file, multiple regions in each bed file, pooled data. 
    beddf = pd.read_csv(inputbed, sep = "\t", header = None)
    beddf.columns = ["chrom", "start", "end", "v3", "v4", "v5"]
        
    flenRange = defaultdict(lambda: [])
    all_flens = []
    
    fa = pyfaidx.Fasta(path_to_fa, as_raw=True, sequence_always_upper=True)
    
    def motif_4bp_at_rstart(chrom, rstart_1based):
        # rstart is 1-based, pyfaidx slicing is 0-based and end-exclusive
        motif = fa[chrom][rstart_1based - 1 : rstart_1based + 3]
        return motif if len(motif) == 4 else None
    
    bedname = str(inputbed).split("/")[-1].replace(".bed", "")
    
    # this can be TSS or TFBS bed file, multiple regions in each bed file, pooled data. 
    beddf = pd.read_csv(inputbed, sep = "\t", header = None)
    beddf.columns = ["chrom", "start", "end", "v3", "v4", "v5"]
        
    flenRange = defaultdict(lambda: [])
    motifRange = defaultdict(lambda: [])
    combineRange = defaultdict(lambda: [])
    
    all_flens = []
    all_motifs = []
    all_combine_flen_motif = []
        
    for region_idx in tqdm(range(beddf.shape[0])):
        region_chrom = beddf.iloc[region_idx]["chrom"]
        region_start = beddf.iloc[region_idx]["start"]
        region_end = beddf.iloc[region_idx]["end"]
        
        tbx = pysam.TabixFile(inputBedfile)
        allReads = Intersecter()
        # try:  # if tbx.fetch do not find any row, next row
        for row in tbx.fetch(region_chrom, region_start, region_end + 1): 
            # all fragments overlaped with this region is collected
            tmp_row = row.split()
            rstart = int(tmp_row[1]) + 1  # convert to 1-based
            rend = int(tmp_row[2])  # end included
            flen = int(tmp_row[4])
            motif = motif_4bp_at_rstart(region_chrom, rstart)
            
            allReads.add_interval(Interval(rstart, rend))  # save the fragments overlap with region
            for i in range(rstart, rend + 1):  # for a single nucleotide site, compute how many reads overlaped span it (include read end point)
                if i >= region_start and i <= region_end:
                    if (fld == True) or (rfe == True): 
                        flenRange[i - region_start - 1000].append(flen)
                        all_flens.append(flen)
                        motifRange[i - region_start - 1000].append(motif)
                        all_motifs.append(motif)
                        combineRange[i - region_start - 1000].append(f"{flen}_{motif}")
                        all_combine_flen_motif.append(f"{flen}_{motif}")
                        
    if fld == True:    
        # ***** FLEN ***** #
        flendf = pd.DataFrame(data = range(min_flen, max_flen + 1), columns = ["flen"])
        for i in flenRange.keys():
            counts = Counter(flenRange[i])
            percentages = {key: (count / sum(counts.values())) for key, count in counts.items()}
            tmpdf = pd.DataFrame.from_dict(percentages, orient = "index").reset_index()
            tmpdf.columns = ["flen", f"position_{i}"]
            flendf = flendf.merge(tmpdf, right_on = "flen", left_on = "flen", how="outer")
            flendf = flendf.fillna(0)
        if save_fld:
            flendf.to_csv(os.path.join(outputdir, f"{sampleid}_{bedname}.tsv"), sep  = "\t", index = False)
    
        # ***** END MOTIF ***** #
        motifdf = pd.DataFrame(data = [f"{i}{j}{k}{l}" for i in ["A", "T", "G", "C"]
                                    for j in ["A", "T", "G", "C"]
                                    for k in ["A", "T", "G", "C"]
                                    for l in ["A", "T", "G", "C"]], columns = ["motif"])
        for i in motifRange.keys():
            counts = Counter(motifRange[i])
            percentages = {key: (count / sum(counts.values())) for key, count in counts.items()}
            tmpdf = pd.DataFrame.from_dict(percentages, orient = "index").reset_index()
            tmpdf.columns = ["motif", f"position_{i}"]
            motifdf = motifdf.merge(tmpdf, right_on = "motif", left_on = "motif", how="outer")
            motifdf = motifdf.fillna(0)
        if save_fld:
            motifdf.to_csv(os.path.join(outputdir, f"{sampleid}_{bedname}.4bpMotif.tsv"), sep  = "\t", index = False)
        
    if rfe == True: 
        # ***** FLEN ***** #
        background_flendf = pd.DataFrame(data = range(min_flen, max_flen + 1), columns = ["flen"])
        counts = Counter(all_flens)
        percentages = {key: (count / sum(counts.values())) for key, count in counts.items()}
        tmpdf = pd.DataFrame.from_dict(percentages, orient = "index").reset_index()
        tmpdf.columns = ["flen", "background"]
        background_flendf = background_flendf.merge(tmpdf, right_on = "flen", left_on = "flen", how="outer")
        background_flendf = background_flendf.fillna(0)
    
        entropydf = pd.DataFrame(data = [item for item in flendf.columns if item != "flen"],
                                columns = ["position"])
        entropydf["entropy"] = entropydf["position"].apply(lambda x:
            -sum([i * np.log2(i) for i in flendf[x].values if i != 0])/np.log2(flendf.shape[0])
        )
        
        def kl_divergence(a, b, epsilon = 10**-6):
            a = [a[i] if a[i] != 0 else epsilon for i in range(len(a))]
            b = [b[i] if b[i] != 0 else epsilon for i in range(len(b))]
            return sum(a[i] * np.log(a[i]/b[i]) for i in range(len(a)))
        entropydf["KLdiv"] = entropydf["position"].apply(lambda x:
                                                            kl_divergence(
                                                                a = flendf[x].to_numpy(),
                                                                b = background_flendf["background"].to_numpy()))
        entropydf.to_csv(os.path.join(outputdir, f"RFE_{sampleid}_{bedname}.tsv"), sep  = "\t", index = False)
    
        # ***** 4bp end motif ***** #
        background_motifdf = pd.DataFrame(data = [f"{i}{j}{k}{l}" for i in ["A", "T", "G", "C"]
                                    for j in ["A", "T", "G", "C"]
                                    for k in ["A", "T", "G", "C"]
                                    for l in ["A", "T", "G", "C"]], columns = ["motif"])
        counts = Counter(all_motifs)
        percentages = {key: (count / sum(counts.values())) for key, count in counts.items()}
        tmpdf = pd.DataFrame.from_dict(percentages, orient = "index").reset_index()
        tmpdf.columns = ["motif", "background"]
        background_motifdf = background_motifdf.merge(tmpdf, right_on = "motif", left_on = "motif", how="outer")
        background_motifdf = background_motifdf.fillna(0)
        
        entropydf = pd.DataFrame(data = [item for item in motifdf.columns if item != "motif"],
                                columns = ["position"])
        entropydf["entropy"] = entropydf["position"].apply(lambda x:
            -sum([i * np.log2(i) for i in motifdf[x].values if i != 0])/np.log2(motifdf.shape[0])
        )
        
        def kl_divergence(a, b, epsilon = 10**-6):
            a = [a[i] if a[i] != 0 else epsilon for i in range(len(a))]
            b = [b[i] if b[i] != 0 else epsilon for i in range(len(b))]
            return sum(a[i] * np.log(a[i]/b[i]) for i in range(len(a)))
        entropydf["KLdiv"] = entropydf["position"].apply(lambda x:
                                                            kl_divergence(
                                                                a = motifdf[x].to_numpy(),
                                                                b = background_motifdf["background"].to_numpy()))
    
        # ***** save the entropy of fragment lengths and the RFE values ***** #
        entropydf.to_csv(os.path.join(outputdir, f"RFE_{sampleid}_{bedname}.4bpMotif.tsv"), sep  = "\t", index = False)
        
    # print(f"Saving the dict combineRange to output pkl file")
    if save_pkl:
        with open(os.path.join(outputdir, f'RFE_combineRange_{sampleid}_{bedname}.pickle'), 'wb') as handle:
            pickle.dump(dict(combineRange), handle, protocol=pickle.HIGHEST_PROTOCOL)

if __name__ == '__main__':
    main()