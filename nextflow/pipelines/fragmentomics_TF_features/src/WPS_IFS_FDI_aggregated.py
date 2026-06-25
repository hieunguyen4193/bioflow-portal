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
import argparse
import warnings
warnings.filterwarnings("ignore")

def main():
    """
    Calculate Windowed Protection Score (WPS), Insertion Fragment Score (IFS), 
    and Fragment Density Index (FDI) for DNA fragments within targeted genomic regions.
    This function processes DNA fragment data from a tabix-indexed BED file and computes
    three fragmentomics features across a set of target regions:
    - WPS: Number of fragments that completely span a sliding window
    - IFS: Insertion fragment score based on fragment counts and lengths relative to chromosome average
    - FDI: Fragment density index combining endpoint distribution and coverage statistics
    Command-line Arguments:
        --input (str): Path to tabix-indexed BED file containing DNA fragments with columns:
                      chrom, start, end, name, fraglen, and other fields
        --output (str): Output directory path where results will be saved
        --inputbed (str): Path to BED file containing target regions for analysis
        --window_size (int): Size of sliding window (in bp) for WPS calculation
        --expand_size (int): Size of flanking regions (in bp) to extend beyond target regions
        --fdi_nb_size (int): Neighborhood size (in bp) for FDI endpoint clustering
        --chromosome_features (str): Path to TSV file with chromosome-level fragment length statistics
                                    (columns: chrom, avgFlen)
    Output:
        Writes CSV file to: {output}/{sampleid}/WPS_IFS_FDI_{bedname}.csv
        Columns: chrom, pos, raw_WPS, IFS, FDI
    Returns:
        None
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
    parser.add_argument('--window_size', 
                        type = int, 
                        required = True, 
                        help = 'Size of sliding windows to calculate scores, e.g. WPS')
    parser.add_argument('--expand_size', 
                        type = int, 
                        required = True, 
                        help = 'Size of the expanding - flanking regions')
    parser.add_argument('--fdi_nb_size', 
                        type = int, 
                        required = True, 
                        help = 'Neightbourhood size for calculating FDI')
    parser.add_argument('--chromosome_features', 
                        type = str, 
                        required = True, 
                        help = 'Path to the chromosome features')
    parser.add_argument('--sampleid',
                    type = str, 
                    required = True, 
                    help = 'Sample ID')
                    
    args = parser.parse_args()
    inputBedfile = args.input
    outputdir = args.output
    inputbed = args.inputbed
    window_size = args.window_size
    fdi_nb_size = args.fdi_nb_size
    chromosome_features = args.chromosome_features
    expand_size = args.expand_size
    sampleid = args.sampleid
    
    tbx = pysam.TabixFile(inputBedfile)
    
    beddf = pd.read_csv(inputbed, sep = "\t", header = None)
    beddf.columns = ["chrom", "start", "end", "v3", "v4", "v5"]
    
    posRange = defaultdict(lambda: [0, 0])
    allReads = Intersecter()
    
    avg_chrom_flendf = pd.read_csv(chromosome_features, sep = "\t")
    
    bedname = str(inputbed).split("/")[-1].replace(".bed", "")
        
    for region_idx in range(beddf.shape[0]):
        region_chrom = beddf.iloc[region_idx]["chrom"]
        region_start = beddf.iloc[region_idx]["start"]
        region_end = beddf.iloc[region_idx]["end"]
        
        window_size = 60
        fdi_nb_size = 10
        # try:  # if tbx.fetch do not find any row, next row
        for row in tbx.fetch(region_chrom, region_start - window_size - 1, region_end + window_size + 1): 
            # all fragments overlaped with this region is collected
            tmp_row = row.split()
            rstart = int(tmp_row[1]) + 1  # convert to 1-based
            rend = int(tmp_row[2])  # end included
            flen = int(tmp_row[4])
    
            allReads.add_interval(Interval(rstart, rend))  # save the fragments overlap with region
            for i in range(rstart, rend + 1):  # for a single nucleotide site, compute how many reads overlaped span it (include read end point)
                if i >= region_start and i <= region_end:
                    posRange[i - region_start - expand_size][0] += 1
            if (rstart >= region_start and rstart <= region_end):  # for a single nucleotide site, compute how many read end point located at this site
                posRange[rstart - region_start - expand_size ][1] += 1
            if rend >= region_start and rend <= region_end:
                posRange[rend - region_start - expand_size][1] += 1
    
    # outLines = []
    all_wps_counts = []
    endpoints = dict()
    region_flen = dict()
    all_fdi = []
    all_ifs = []
    gcount = dict()
    bcount = dict()
    
    for region_idx in range(beddf.shape[0]):
        region_chrom = beddf.iloc[region_idx]["chrom"]
        region_start = beddf.iloc[region_idx]["start"]
        region_end = beddf.iloc[region_idx]["end"]
        for pos in range(region_start, region_end + 1):
            endpoints[pos - region_start - expand_size] = list()
            region_flen[pos - region_start - expand_size] = list()
            rstart, rend = pos - window_size, pos + window_size
            gcount[pos - region_start - expand_size] = 0
            bcount[pos - region_start - expand_size] = 0
            
            for read in allReads.find(rstart, rend):
                region_flen[pos - region_start - expand_size].append(read.end - read.start)
                if (read.start > rstart) or (read.end < rend):
                    bcount[pos - region_start - expand_size] += 1  # fragments located in window
                    if read.start > rstart:
                        endpoints[pos - region_start - expand_size].append(read.start)
                    elif read.end < rend:
                        endpoints[pos - region_start - expand_size].append(read.end)
                else:
                    gcount[pos - region_start - expand_size] += 1  # fragments spanned window
    
    for pos in range(-expand_size, expand_size + 1):
        wps_count = gcount[pos] - bcount[pos]
        all_wps_counts.append(wps_count)
        if len(endpoints[pos]) != 0:
            # calculate FDI
            endpointdf = pd.DataFrame(data = endpoints[pos], columns = ["pos"])
            endpointdf["nb"] = endpointdf["pos"].apply(
                lambda x: endpointdf[abs(endpointdf["pos"] - x) <= fdi_nb_size ].shape[0]
            )
            
            window_std_coverage = np.std([posRange[i][0] for i in range(pos - window_size, 
                                                                        pos + window_size + 1) if posRange[i][0] != 0 ])
            edi = np.sum([0.5**i for i in endpointdf.nb.to_list()]) * (1/endpointdf.shape[0])
            fdi = window_std_coverage * edi
        else:
            fdi = 0
        all_fdi.append(fdi)
        
        # calculate IFS
        n = bcount[pos]
        l = np.mean(region_flen[pos])
        L = avg_chrom_flendf[avg_chrom_flendf["chrom"] == region_chrom]["avgFlen"].values[0]
        ifs = n * (1 + (l/L) )
        all_ifs.append(ifs)
    
    outputdf = pd.DataFrame.from_dict(
        {
            "chrom": region_chrom,
            "pos" : range(-expand_size, expand_size + 1),
            "raw_WPS": all_wps_counts,
            "IFS": all_ifs,
            "FDI": all_fdi
        }
    )
    outputdf.to_csv(os.path.join(outputdir, f"WPS_IFS_FDI_{sampleid}_{bedname}.csv"), sep  = "\t", index = False)

if __name__ == '__main__':
    main()