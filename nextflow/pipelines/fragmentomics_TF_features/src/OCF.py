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
# ***** helper function ***** #
# and example commands, input args
# min_flen = 50
# max_flen = 350
# inputBedfile = "/Users/hieunguyen/outdir/ecd_wgs_and_enriched_features/ABC123.sorted_region_Full_fraglen_50_350.sorted.bed.gz"
# outputdir = "/Users/hieunguyen/outdir/ecd_wgs_and_enriched_features"
# inputbed = "/Users/hieunguyen/src/ecd_wgs_and_enriched_features/preprocessed_resources/TFBS/Mad3.Top1000sites_1000.hg19.bed"

def main():
    """
    Calculate Orientation-aware Cleavage Frequency (OCF) for DNA fragments across genomic regions.
    This function parses command-line arguments to process a BED file containing DNA fragments
    and calculate OCF metrics for specified genomic regions. OCF is computed based on fragment
    start and end positions within a defined window around the midpoint of each region.
    Command-line Arguments:
        --input (str): Path to the indexed BED file (.sorted.bed.gz) containing DNA fragments
                      with columns: chrom, start, end. Required.
        --inputbed (str): Path to the BED file containing target genomic regions for analysis
                         with columns: chrom, start, end (additional columns optional). Required.
        --output (str): Output directory where results will be saved. Required.
        --min_flen (int): Minimum fragment length threshold for inclusion in OCF calculation. Required.
        --max_flen (int): Maximum fragment length threshold for inclusion in OCF calculation. Required.
    Returns:
        None
    Output:
        Generates a TSV file at {output}/OCF/{sampleid}_{bedname}.tsv containing:
            - chrom: Chromosome identifier
            - start: Start position of region
            - end: End position of region
            - OCF: Calculated OCF score (difference between right and left cleavage patterns)
    Notes:
        - Creates output directory structure if it does not exist
        - Fragment length filtering is applied during OCF calculation
        - OCF is computed using a 20bp window at positions 50-70bp left and right of region midpoint
        - Requires indexed input BED file (pysam.TabixFile compatible)
    """
    parser = argparse.ArgumentParser()
    parser.add_argument('--input', 
                        type = str, 
                        required = True, 
                        help = 'Path to the input BED file containing DNA fragments')
    parser.add_argument('--inputbed', 
                        type = str, 
                        required = True, 
                        help = 'Path to the input BED file containing the regions')
    parser.add_argument('--output', 
                        type = str, 
                        required = True, 
                        help = 'Output directory to save results')
    parser.add_argument('--min_flen', 
                        type = int, 
                        required = True, 
                        help = 'Minimum fragment length')
    parser.add_argument('--max_flen', 
                        type = int, 
                        required = True, 
                        help = 'Maximum fragment length')
    
    args = parser.parse_args()
    inputBedfile = args.input
    inputbed = args.inputbed
    outputdir = args.output
    min_flen = args.min_flen
    max_flen = args.max_flen
    os.system(f"mkdir -p {os.path.join(outputdir, 'OCF')}")
    def calculate_OCF(  converted_bed_file,
                        region_chrom,
                        region_start,
                        region_end,
                        min_flen,
                        max_flen):
        tbx = pysam.TabixFile(converted_bed_file)
        fetched_reads = tbx.fetch(region_chrom, region_start, region_end)
        covPOS = defaultdict(lambda: [0, 0, 0])
        for row in fetched_reads:
            tmp_row = row.split()
            rstart = int(tmp_row[1]) + 1  # convert to 1-based
            rend = int(tmp_row[2])  # end included
            flen = rend - rstart
            for i in range(rstart, rend + 1):  # for a single nucleotide site, compute how many reads overlaped span it (include read end point)
                if i >= region_start and i <= region_end:
                    if (flen >= min_flen) and (flen <= max_flen):
                        covPOS[i][0] += 1
            if rstart >= region_start and rstart <= region_end:  # consider read start point, U end
                covPOS[rstart][1] += 1
        
            if rend >= region_start and rend <= region_end:  # consider read start point, D end
                covPOS[rend][2] += 1
        
        midpoint = int((region_start + region_end) / 2)
        left_OCF = sum([covPOS[x][2] for x in range(midpoint - 70, midpoint - 50)]) - sum(
                    [covPOS[x][1] for x in range(midpoint - 70, midpoint - 50)]
                )
        right_OCF = sum([covPOS[x][1] for x in range(midpoint + 50, midpoint + 70)]) - sum(
            [covPOS[x][2] for x in range(midpoint + 50, midpoint + 70)]
        )
        
        OCF = left_OCF + right_OCF
        return OCF, covPOS
    
    bedname = str(inputbed).split("/")[-1].replace(".bed", "")
    sampleid = str(inputBedfile).split("/")[-1].replace(".sorted.bed.gz", "")
    
    beddf = pd.read_csv(inputbed, sep = "\t", header = None)
    beddf.columns = ["chrom", "start", "end", "v3", "v4", "v5"]
    
    outputdf = pd.DataFrame()
    
    for region_idx in range(beddf.shape[0]):
        region_chrom = beddf.iloc[region_idx]["chrom"]
        region_start = beddf.iloc[region_idx]["start"]
        region_end = beddf.iloc[region_idx]["end"]
        
        ocf, _ = calculate_OCF(converted_bed_file = inputBedfile,
                                    region_chrom = region_chrom,
                                    region_start = region_start,
                                    region_end = region_end, 
                                   min_flen = min_flen, 
                                   max_flen = max_flen)
        tmpdf = pd.DataFrame.from_dict(
            {
                "chrom": region_chrom,
                "start": region_start,
                "end": region_end,
                "OCF": ocf
            }, orient = "index"
        ).T
        outputdf = pd.concat([outputdf, tmpdf], axis = 0)
        # covPOSdf = pd.DataFrame.from_dict(covPOS, orient = "index").T
        # covPOSdf["type"] = ["coverage", "fragment_start", "fragment_end"]
    outputdf.to_csv(os.path.join(outputdir, "OCF", f"{sampleid}_{bedname}.tsv"), sep = "\t", index = False)
if __name__ == '__main__':
    main()