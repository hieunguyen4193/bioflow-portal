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
    Main function to calculate WPS (Windowed Positioning Score), IFS (Intra-Fragment Size), 
    and FDI (Fragment Endpoint Dispersion Index) metrics for genomic regions.
    This script processes DNA fragment data from a BAM/BED file and computes three key 
    fragmentomics features across specified genomic regions:
    - WPS: Measures nucleosome positioning by quantifying fragments that span a window
    - IFS: Captures intra-fragment size patterns relative to chromosome averages
    - FDI: Quantifies fragment endpoint clustering and dispersion patterns
    Command-line Arguments:
        --input (str): Path to input gzipped BED file containing DNA fragments
                      Format: chrom, start, end, name, fragment_length
                      Must be sorted and indexed with tabix
        --output (str): Output directory path where results will be saved
                       Creates subdirectory: {output}/WPS_IFS_FDI/{bedname}/
        --inputbed (str): Path to BED file containing target genomic regions
                         Format: chrom, start, end, [optional columns]
                         Each region will be analyzed independently
        --window_size (int): Size of sliding window (bp) for WPS calculation
                            Typical value: 120 bp (nucleosome-sized)
        --fdi_nb_size (int): Neighborhood size (bp) for FDI endpoint clustering analysis
                            Typical value: 10 bp
        --chromosome_features (str): Path to TSV file with chromosome-level fragment statistics
                                    Required columns: chrom, avgFlen
    Output:
        Generates CSV files for each genomic region with columns:
        - chrom: Chromosome name
        - pos: Genomic position (1-based, inclusive)
        - raw_WPS: Windowed Positioning Score
        - IFS: Intra-Fragment Size score
        - FDI: Fragment endpoint Dispersion Index
        Files saved as: WPS_IFS_FDI_{sampleid}_{chrom}_{start}_{end}.csv
    Note:
        Input BED file must be bgzip-compressed and indexed with tabix for efficient retrieval.
        Requires external packages: pysam, pandas, numpy, bx-python
    """
    # ***** helper functions ***** #
    def calculate_rawWPS_IFS_FDI(converted_bed_file, 
                                region_chrom,
                                region_start,
                                region_end,
                                window_size, 
                                fdi_nb_size,
                                avg_chrom_flendf):
        tbx = pysam.TabixFile(inputBedfile)
        posRange = defaultdict(lambda: [0, 0])
        
        allReads = Intersecter()
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
                    posRange[i][0] += 1
            if (rstart >= region_start and rstart <= region_end):  # for a single nucleotide site, compute how many read end point located at this site
                posRange[rstart][1] += 1
            if rend >= region_start and rend <= region_end:
                posRange[rend][1] += 1
        
        # outLines = []
        all_wps_counts = []
        endpoints = dict()
        region_flen = dict()
        all_fdi = []
        all_ifs = []
        
        for pos in range(region_start, region_end + 1):
            endpoints[pos] = list()
            region_flen[pos] = list()
            rstart, rend = pos - window_size, pos + window_size
            gcount, bcount = 0, 0
            for read in allReads.find(rstart, rend):
                region_flen[pos].append(read.end - read.start)
                if (read.start > rstart) or (read.end < rend):
                    bcount += 1  # fragments located in window
                    if read.start > rstart:
                        endpoints[pos].append(read.start)
                    elif read.end < rend:
                        endpoints[pos].append(read.end)
                else:
                    gcount += 1  # fragments spanned window
            covCount, startCount = posRange[pos]
            # chrom: chromatin, pos: position in the genome, covCount:how many reads span this site, startCount: how many reads end point located
            # in this site, gcount-bcount: WPS
            wps_count = gcount - bcount
            # outLines.append("%s\t%d\t%d\t%d\t%d\n" % (region_chrom, pos, covCount, startCount, wps_count))
            all_wps_counts.append(gcount - bcount)
            if len(endpoints[pos]) != 0:
                # calculate FDI
                endpointdf = pd.DataFrame(data = endpoints[pos], columns = ["pos"])
                endpointdf["nb"] = endpointdf["pos"].apply(
                    lambda x: endpointdf[abs(endpointdf["pos"] - x) <= fdi_nb_size ].shape[0]
                )
                
                window_std_coverage = np.std([posRange[i][0] for i in range(pos - window_size, pos + window_size + 1)])
                edi = np.sum([0.5**i for i in endpointdf.nb.to_list()]) * (1/endpointdf.shape[0])
                fdi = window_std_coverage * edi
            else:
                fdi = 0
            all_fdi.append(fdi)
        
            # calculate IFS
            n = bcount
            l = np.mean(region_flen[pos])
            L = avg_chrom_flendf[avg_chrom_flendf["chrom"] == region_chrom]["avgFlen"].values[0]
            ifs = n * (1 + (l/L) )
            all_ifs.append(ifs)
            
        outputdf = pd.DataFrame.from_dict(
            {
                "chrom": region_chrom,
                "pos" : range(region_start, region_end + 1),
                "raw_WPS": all_wps_counts,
                "IFS": all_ifs,
                "FDI": all_fdi
            }
        )
        return outputdf

    # ***** end of helper function ***** #
    # ***** main run ***** #
    # example input args
    # inputBedfile = "/Users/hieunguyen/outdir/ecd_wgs_and_enriched_features/ABC123.sorted_region_Full_fraglen_50_350.sorted.bed.gz"
    # outputdir = "/Users/hieunguyen/outdir/ecd_wgs_and_enriched_features"
    # inputbed = "/Users/hieunguyen/src/ecd_wgs_and_enriched_features/preprocessed_resources/TFBS/Mad3.Top1000sites_1000.hg19.bed"
    # chromosome_features = "/Users/hieunguyen/outdir/ecd_wgs_and_enriched_features/ABC123_splitChroms/std_avg_shannon.tsv"
    # fdi_nb_size = 10
    # window_size = 120
    
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
    parser.add_argument('--fdi_nb_size', 
                        type = int, 
                        required = True, 
                        help = 'Neightbourhood size for calculating FDI')
    parser.add_argument('--chromosome_features', 
                        type = str, 
                        required = True, 
                        help = 'Path to the chromosome features')
    
    args = parser.parse_args()
    inputBedfile = args.input
    outputdir = args.output
    inputbed = args.inputbed
    window_size = args.window_size
    fdi_nb_size = args.fdi_nb_size
    chromosome_features = args.chromosome_features
    
    avg_chrom_flendf = pd.read_csv(chromosome_features, sep = "\t")
    
    os.system(f"mkdir -p {outputdir}/WPS_IFS_FDI")
    
    sampleid = inputBedfile.split("/")[-1].split("_region")[0]
    bedname = str(inputbed).split("/")[-1].replace(".bed", "")
    
    # this can be TSS or TFBS bed file, multiple regions in each bed file, pooled data. 
    beddf = pd.read_csv(inputbed, sep = "\t", header = None)
    beddf.columns = ["chrom", "start", "end", "v3", "v4", "v5"]
    
    os.system(f"mkdir -p {os.path.join(outputdir, "WPS_IFS_FDI", bedname)}")
    for region_idx in range(beddf.shape[0]):
        region_chrom = beddf.iloc[region_idx]["chrom"]
        region_start = beddf.iloc[region_idx]["start"]
        region_end = beddf.iloc[region_idx]["end"]
        
        scoredf = calculate_rawWPS_IFS_FDI(converted_bed_file = inputBedfile, 
                                 region_chrom = region_chrom,
                                 region_start = region_start,
                                 region_end = region_end,
                                 window_size = window_size, 
                                 fdi_nb_size = fdi_nb_size,
                                 avg_chrom_flendf = avg_chrom_flendf)
        scoredf.to_csv(os.path.join(outputdir, 
                                    "WPS_IFS_FDI", 
                                    bedname, 
                                    f"WPS_IFS_FDI_{sampleid}_{region_chrom}_{region_start}_{region_end}.csv"), 
                       sep = "\t", 
                       index = False)
        
if __name__ == '__main__':
    main()