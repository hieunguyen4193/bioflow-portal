import pandas as pd 
import os
import pathlib 
import matplotlib.pyplot as plt 
import seaborn as sns
import numpy as np 
import pysam 
from tqdm import tqdm
import argparse
import sys
from collections import defaultdict
from bx.intervals.intersection import Intersecter, Interval
import warnings
warnings.filterwarnings("ignore")
# input args: examples
# inputbam = "/Users/hieunguyen/storage/WGS_bam/outputdir/input.sorted.bam"
# outputdir = "/Users/hieunguyen/storage/WGS_bam/outputdir"
# beddir = "/Users/hieunguyen/src/ecd_wgs_and_enriched_features/preprocessed_resources/TFBS"
# inputcna = "/Users/hieunguyen/storage/WGS_bam/outputdir/input.bin100kb.bed"
# covfile = "/Users/hieunguyen/storage/WGS_bam/outputdir/input.avgGenomeCov.tsv"
# plot_cov = False
# mapq = 30

def main():
    """
    Generate coverage profiles for transcription factor binding sites (TFBS) from BAM or BED files.
    This function processes genomic data to calculate read-level or fragment-level coverage
    around TFBS regions, normalizes coverage by genome-wide mean coverage and copy number
    alterations (CNA), and outputs aggregated coverage profiles.
    Command-line Arguments:
        --input (str, required): Path to the input BAM file or indexed BED file
        --output (str, required): Path to directory for saving output files
        --inputbed (str, required): Path to BED file containing TFBS regions (chrom, start, end, ...)
        --cna (str, required): Path to CNA output file with columns (chrom, start, end, log2.ratio)
        --cov (str, required): Path to genome coverage file with per-chromosome mean coverage
        --count_mode (str, required): Coverage counting mode - "read" for read-level or "fragment" for fragment-level
        --mapq (int, optional): Minimum mapping quality threshold for reads (default: 30)
        --expand_size (int, optional): Window size to expand around TFBS center position (default: 1000)
        --min_flen (int, optional): Minimum fragment length for fragment-level counting (default: 50)
        --max_flen (int, optional): Maximum fragment length for fragment-level counting (default: 350)
    Output:
        Creates TSV file at {output}/{sampleid}/{tf}.tsv containing:
            - Position: Relative position from TFBS center (-expand_size to expand_size)
            - Mean.Cov: Mean normalized coverage across all TFBS in the region set
            - Raw.Cov: Mean raw (non-normalized) coverage
            - num_TFBS: Number of TFBS sites with non-zero coverage at each position
    Processing:
        1. Reads genome-wide mean coverage from coverage file
        2. Loads TFBS regions from BED file
        3. For each TFBS:
            - Extracts coverage using specified count_mode (read or fragment level)
            - Normalizes by genome mean coverage and CNA log2 ratio
            - Stores normalized and raw coverage for aggregation
        4. Aggregates coverage across all TFBS using mean and count statistics
        5. Outputs aggregated profile to TSV file
    Note:
        - Skips processing if output file already exists
        - Fragment-level mode requires indexed BED/BAM file for TabixFile access
        - CNA normalization uses 2^log2.ratio as copy number factor
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
    parser.add_argument('--inputbed', 
                    type = str, 
                    required = True, 
                    help = 'Path to bed file of a region. Each file is a TF, a TF contain topN TFBS')
    parser.add_argument('--cna', 
                        type = str, 
                        required = True, 
                        help = 'Path to the CNA output file')
    parser.add_argument('--cov', 
                        type = str, 
                        required = True, 
                        help = 'Path to the genome coverage file')
    parser.add_argument('--mapq', 
                        type = int,
                        default = 30,
                        required = False, 
                        help = 'Min quality of reads to be used in the counting process')
    parser.add_argument('--expand_size', 
                        type = int,
                        default = 1000,
                        required = False, 
                        help = 'Min quality of reads to be used in the counting process')
    parser.add_argument('--count_mode', 
                        type = str, 
                        required = True, 
                        help = 'count mode: read level or fragment level')
    parser.add_argument('--min_flen', 
                        type = int,
                        default = 50,
                        required = False, 
                        help = 'Min fragment length')
    parser.add_argument('--max_flen', 
                        type = int,
                        default = 350,
                        required = False, 
                        help = 'Max fragment length')
    parser.add_argument('--sampleid',
                    type = str, 
                    required = True, 
                    help = 'Sample ID')

    args = parser.parse_args()
    inputfile = args.input
    
    outputdir = args.output
    # beddir = args.beddir
    inputbed = args.inputbed
    inputcna = args.cna
    covfile = args.cov
    mapq = args.mapq
    min_flen = args.min_flen
    max_flen = args.max_flen
    expand_size = args.expand_size
    count_mode = args.count_mode
    sampleid = args.sampleid
    
    os.system(f"mkdir -p {outputdir}")
    
    inputbed = str(inputbed)
    # tfbsdir = os.path.join(outputdir, "coverage_profile")
    tfbsdir = outputdir
    
    tf = inputbed.split("/")[-1].replace(".bed", "")
    
    if count_mode == "read":
        bamfile = pysam.AlignmentFile(inputfile, 'rb')
    elif count_mode == "fragment":
        tbx = pysam.TabixFile(inputfile)

    # ***** read CNA file 
    cnadf = pd.read_csv(inputcna, sep = "\t", header = None)
    cnadf.columns = ["chrom", "start", "end", "log2.ratio"]
    cnadf = cnadf[cnadf["log2.ratio"].isna() == False]
    

    if os.path.isfile(os.path.join(tfbsdir, f"{tf}.tsv")) == False:
        os.system(f"mkdir -p {tfbsdir}")
        covdf = pd.read_csv(covfile, sep = "\t", header = None)
        mean_coverage = covdf[covdf[0] == "genome"][1].values[0]
        
        beddf = pd.read_csv(inputbed, sep = "\t", header = None)
        
        # reading in input bam file
        beddf.columns = ["chrom", "start", "end", "v3", "v4", "v5"]
        
        # aggdf = pd.DataFrame(data = range(-expand_size, expand_size + 1), columns = ["Relative.Position"])
        agg_output_normCov_strings = dict()
        agg_output_rawCov_strings = dict()

        for k in range(-expand_size - 1 , expand_size + 1):
            agg_output_normCov_strings[k] = list()
            agg_output_rawCov_strings[k] = list()
        keyrange = range(-expand_size - 1 , expand_size + 1)
        
        for tfbs_i in range(beddf.shape[0]):
            region_chrom = beddf.iloc[tfbs_i]["chrom"]
            region_start = beddf.iloc[tfbs_i]["start"]
            region_end = beddf.iloc[tfbs_i]["end"]
            
            pos = int(np.floor(region_start + 0.5*(region_end - region_start)))
            
            if count_mode == "read":
                # bamfile = pysam.AlignmentFile(inputfile, 'rb')
                # print("Counting read-level coverage")
                # ***** using bam file, read level
                c = bamfile.count_coverage(region_chrom, region_start, region_end + 1, quality_threshold = mapq)
                coverage = list()
                for i in range(0,len(c[0])):
                    coverage.append(c[0][i]+c[1][i]+c[2][i]+c[3][i])  
        
                if len(coverage) < region_end - region_start + 1:
                    for i in range(region_end - region_start + 1 - len(coverage)):
                        coverage.append(0)
            elif count_mode == "fragment":
                # print("Counting fragment-level coverage")
                # ***** using bed file, fragment level
                # tbx = pysam.TabixFile(inputfile)
                posRange = defaultdict(lambda: [0])
                allReads = Intersecter()
                # try:  # if tbx.fetch do not find any row, next row
                for row in tbx.fetch(region_chrom, region_start, region_end + 1): 
                    # all fragments overlaped with this region is collected
                    tmp_row = row.split()
                    rstart = int(tmp_row[1]) + 1  # convert to 1-based
                    rend = int(tmp_row[2])  # end included
                    flen = int(tmp_row[4])
                    
                    allReads.add_interval(Interval(rstart, rend))  # save the fragments overlap with region
                    for i in range(rstart, rend + 1):  # for a single nucleotide site, compute how many reads overlaped span it (include read end point)
                        if i >= region_start and i <= region_end:
                            if (flen >= min_flen) and (flen <= max_flen):
                                posRange[i][0] += 1
                coverage = []
                for i in range(region_start, region_end + 1):
                    if i in posRange.keys():
                        coverage.append(posRange[i][0])
                    else:
                        coverage.append(0)
                        
            # ***** plot ***** #
            # if plot_cov:
            #     plt.figure(figsize = (20, 5))
            #     plt.plot(coverage)

            cna_val = cnadf[(cnadf["chrom"] == region_chrom) & 
                (cnadf["start"] < pos) & (cnadf["end"] > pos)]["log2.ratio"].values
            
            if len(cna_val) == 1: 
                normcov = float(np.power(2,cna_val)[0])
            else:
                normcov = 1
                
            norm_coverage = [(float(coverage[i]) / mean_coverage) / normcov for i in range(len(coverage))] 
            
            # if plot_cov:
            #     plt.plot(norm_coverage)
    
            # ***** save the file: each position in the TFBS window, with raw coverage and normalized coverage
            # tmp_outputfile = os.path.join(tfbsdir, sampleid, tf, f"{region_chrom}_{region_start}_{region_end}_mean_cov.tsv")
            # f = open(tmp_outputfile, "w")
            # f.write(f"chrom\tPosition\tNorm.Cov\tRaw.Cov\n")
            # all_positions = range(region_start, region_end + 1)
            
            # output_strings = []

            for j in range(len(coverage)):
                # output_strings.append(
                #     f"{region_chrom}\t{all_positions[j]}\t{norm_coverage[j]}\t{coverage[j]}\n"
                # )
                agg_output_normCov_strings[keyrange[j]].append(norm_coverage[j])
                agg_output_rawCov_strings[keyrange[j]].append(coverage[j])
            # f.writelines(output_strings)
            # f.close()
            
            # do not generate pandas dataframe, slow performance. 
            # tfbsdf = pd.DataFrame(data = norm_coverage, columns = ["Norm.Cov"])
            # tfbsdf["Raw.Cov"] = coverage
            # tfbsdf["Position"] = range(region_start, region_end + 1)
            # tfbsdf["chrom"] = region_chrom
            # tfbsdf = tfbsdf[["chrom", "Position", "Norm.Cov", "Raw.Cov"]]
            # tfbsdf["Relative.Position"] = range(-expand_size - 1, expand_size + 1)
            # tfbsdf.to_csv(os.path.join(tfbsdir, sampleid, tf, f"{region_chrom}_{region_start}_{region_end}_mean_cov.tsv"),
            #                sep = "\t", index = False)
            # tmpdf = tfbsdf[["Relative.Position", "Norm.Cov", "Raw.Cov"]].copy()
            # tmpdf.columns = ["Relative.Position", f"NormCov_{tfbs_i}", f"RawCov_{tfbs_i}"]
            # aggdf = aggdf.merge(tmpdf, right_on = "Relative.Position", left_on = "Relative.Position")
        avg_rawCov = [np.mean(agg_output_rawCov_strings[i]) for i in agg_output_rawCov_strings.keys()]
        avg_normCov = [np.mean(agg_output_normCov_strings[i]) for i in agg_output_normCov_strings.keys()]
        num_tfbs = [len([j for j in agg_output_normCov_strings[i] if j != 0]) for i in agg_output_normCov_strings.keys()]

        outputdf = pd.DataFrame(
            data = range(- expand_size - 1, expand_size + 1), columns = ["Position"]
        )
        outputdf["Mean.Cov"] = avg_normCov
        outputdf["Raw.Cov"] = avg_rawCov
        outputdf["num_TFBS"] = num_tfbs
        outputdf = outputdf[outputdf["Position"].isin(range(-expand_size, expand_size + 1))]
        # if plot_cov:
        #     plt.plot(aggdf.set_index("Relative.Position").mean(axis = 1).values)

        outputdf.to_csv(os.path.join(tfbsdir, f"{sampleid}_{tf}.tsv"), sep = "\t")

        ##### do not run
        # outputdf = pd.DataFrame(
        #     data = range(-expand_size, expand_size + 1), columns = ["Position"]
        # )
        # outputdf["Mean.Cov"] = aggdf.set_index("Relative.Position").mean(axis = 1).values
        # outputdf["Mean.Cov"] = aggdf[[item for item in aggdf.columns if "NormCov_" in item]].mean(axis = 1).values
        # outputdf["num_TFBS"] = aggdf[[item for item in aggdf.columns if "tfbs" in item]].apply(lambda x: len([i for i in x if i != 0]), axis = 1)
        
    else:
        print(f"Result for TF {tf} exists")

if __name__ == '__main__':
    main()