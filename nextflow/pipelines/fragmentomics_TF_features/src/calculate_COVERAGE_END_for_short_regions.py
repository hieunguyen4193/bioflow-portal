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
import warnings 
import argparse
warnings.filterwarnings("ignore")
# ***** helper function ***** #

# inputBedfile = "/Users/hieunguyen/outdir/ecd_wgs_and_enriched_features/ABC123.sorted_region_Full_fraglen_50_350.sorted.bed.gz"
# outputdir = "/Users/hieunguyen/outdir/ecd_wgs_and_enriched_features"
# inputbed = "/Users/hieunguyen/src/ecd_wgs_and_enriched_features/preprocessed_resources/TFBS/Mad3.Top1000sites_1000.hg19.bed"

def main():
    """
    Calculate COVERAGE and END features for short genomic regions.
    This module processes BAM files and BED files to compute fragment-level coverage 
    statistics for SHORT regions. It calculates three main metrics:
    - COVERAGE: Count of fragments spanning the entire region
    - END: Count of fragments located within the region window
    - flen_ratio: Log2 ratio of mean fragment lengths between cut and spanning fragments
    Args:
        --input (str): Path to the input BAM file (sorted and indexed in BED.GZ format)
        --output (str): Path to directory where output results will be saved
        --bed (str): Path to the input BED file containing the genomic regions to analyze
    Returns:
        None. Outputs a TSV file with COVERAGE, END, and flen_ratio metrics for each region.
    Raises:
        FileNotFoundError: If input BAM or BED files do not exist
        ValueError: If BED file format is invalid or regions contain no reads
    Note:
        This function is designed specifically for short regions. For long regions, 
        the fragment length ratio (flen_ratio) between spanning and cut fragments 
        may not be meaningful as most fragments will be cut.
    Workflow:
        1. Parse command-line arguments for input/output paths
        2. Read BED file containing regions of interest
        3. For each region, query the indexed BAM file for overlapping fragments
        4. Classify fragments as spanning (entire region) or cut (partial overlap)
        5. Calculate coverage metrics and fragment length statistics
        6. Write results to output TSV file organized by region
    Example:
        python script.py --input sample.sorted.bed.gz --output ./results --bed regions.bed
    """
    parser = argparse.ArgumentParser()
    parser.add_argument('--input', 
                        type = str, 
                        required = True, 
                        help = 'Path to the input bam file')
    parser.add_argument('--output', 
                        type = str, 
                        required = True, 
                        help = 'Path to save output')
    parser.add_argument('--bed', 
                        type = str, 
                        required = True, 
                        help = 'Path to the input BED file containing the regions')
    args = parser.parse_args()
    inputBedfile = args.input
    outputdir = args.output
    inputbed = args.bed
    
    def flanking_and_centered_ratio_features(converted_bed_file,
                                            region_chrom,
                                            region_start,
                                            region_end):
        tbx = pysam.TabixFile(converted_bed_file)
        allReads = Intersecter()
        for row in tbx.fetch(region_chrom, region_start - 1, region_end + 1): 
            tmp_row = row.split()
            rstart = int(tmp_row[1]) + 1  # convert to 1-based
            rend = int(tmp_row[2])  # end included
            flen = int(tmp_row[4])
            allReads.add_interval(Interval(rstart, rend)) 
        
        gcount, bcount = 0, 0
        span_flen = []
        cut_flen = []
        for read in allReads.find(region_start, region_end):
            if (read.start > region_start) or (read.end < region_end):
                bcount += 1  # fragments located in window
                cut_flen.append(read.end - read.start)
            else:
                gcount += 1  # fragments spanned window
                span_flen.append(read.end - read.start)
        
        COVERAGE = gcount
        END = bcount
        
        flen_ratio = np.log2(np.mean(cut_flen)/np.mean(span_flen))
        # to do: RFE, instead of just pure ratio, calculate shannon entropy or KL Divergence between fragment length distributions
        # of span flen and cut flen.
        return COVERAGE, END, flen_ratio
    
    # this apply for short regions only. 
    # for long regions, the flen_ratio between span-flen and cut-flen does not make sense. 
    
    bedname = str(inputbed).split("/")[-1].replace(".bed", "")
    sampleid = str(inputBedfile).split("/")[-1].replace(".sorted.bed.gz", "")
    
    beddf = pd.read_csv(inputbed, sep = "\t", header = None)
    beddf.columns = ["chrom", "start", "end", "v3", "v4", "v5"]
    
    os.system(f"mkdir -p {os.path.join(outputdir, 'COVERAGE_END_FOR_SHORT_REGIONS', bedname)}")
    outputdf = pd.DataFrame()
    for i in tqdm(range(beddf.shape[0])):
        region_chrom = beddf.loc[i]["chrom"]
        region_start = beddf.loc[i]["start"]
        region_end = beddf.loc[i]["end"]
        
        COVERAGE, END, flen_ratio = flanking_and_centered_ratio_features( 
            converted_bed_file = inputBedfile,
            region_chrom = region_chrom,
            region_start = region_start,
            region_end = region_end)
        tmpdf = pd.DataFrame.from_dict(
            {
               "region_chrom" : region_chrom,
                "region_start" : region_start,
                "region_end" : region_end,
                "COVERAGE" : COVERAGE,
                "END" : END,
                "flen_ratio" : flen_ratio
            }, orient = "index"
        ).T
        outputdf = pd.concat([outputdf, tmpdf], axis = 0)
    outputdf = outputdf.reset_index().drop("index", axis = 1)
    outputdf.to_csv(os.path.join(outputdir, "COVERAGE_END_FOR_SHORT_REGIONS", bedname, f"{sampleid}.tsv"))

if __name__ == '__main__':
    main()