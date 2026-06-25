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
import sys 


# helper functions
def isSoftClipped(cigar):
    """
    see here for more information about this function
    references:
        https://pysam.readthedocs.io/en/latest/api.html
        https://davetang.org/wiki/tiki-index.php?page=SAM
    """
    for (op, count) in cigar:
        if op in [4, 5, 6]:
            return True
    return False
    
def read_pair_generator(bam, region_string=None):
    """
    Generate read pairs in a BAM file or within a region string.
    Reads are added to read_dict until a pair is found.
    reference:
        https://www.biostars.org/p/306041/
    Function taken from cfDNApipe github and modified.
    """
    read_dict = defaultdict(lambda: [None, None])
    for read in bam.fetch(region=region_string):
        # filter reads
        if read.is_unmapped or read.is_qcfail or read.is_duplicate:
            continue
        if not read.is_paired:
            continue
        if not read.is_proper_pair:
            continue
        if read.is_secondary or read.is_supplementary:
            continue
        if read.mate_is_unmapped:
            continue
        if read.rnext != read.tid:
            continue
        if read.template_length == 0:
            continue
        if isSoftClipped(read.cigar):
            continue

        qname = read.query_name
        if qname not in read_dict:
            if read.is_read1:
                read_dict[qname][0] = read
            else:
                read_dict[qname][1] = read
        else:
            if read.is_read1:
                yield read, read_dict[qname][1]
            else:
                yield read_dict[qname][0], read
            del read_dict[qname]
    return read_dict

def main():
    """
    Convert BAM file to BED file with fragment length filtering and optional sorting.
    This function parses command-line arguments to configure BAM to BED conversion parameters,
    reads paired-end alignments from a BAM file, filters by mapping quality and fragment length,
    and outputs genomic coordinates in BED format with optional gzip compression and indexing.
    Command-line Arguments:
        --inputbam (str, required): Path to the input BAM file
        --outputdir (str, required): Output directory to save results
        --mapq (int, required): Minimum mapping quality threshold for reads
        --region (str, required): Region string to fetch reads (e.g., 'chr1:1000-2000' or 'full')
        --min_frag_length (int, required): Minimum fragment length to consider
        --max_frag_length (int, required): Maximum fragment length to consider
        --gzipbed (bool, optional): Gzip and index the output BED file. Default is True
        --sort_by_readID (bool, optional): Sort output BED file by read ID. Default is False
        --rerun: Flag to force rerun if output file already exists
    Returns:
        None
        - Generates BED file(s) with columns: chrom, chromStart, chromEnd, readName, fragmentLength
        - If gzipbed=True: creates sorted, gzip-compressed BED file with tabix index
    """
    parser = argparse.ArgumentParser()
    parser.add_argument('--inputbam', 
                        type = str, 
                        required = True, 
                        help = 'Path to the input bam file')
    parser.add_argument('--outputdir', 
                        type = str, 
                        required = True, 
                        help = 'Output directory to save results')
    
    parser.add_argument('--mapq', 
                        type = int, 
                        required = True, 
                        help = 'Minimum mapping quality to consider a read')
    parser.add_argument('--region', 
                        type = str, 
                        required = True, 
                        help = 'Region string to fetch reads from the bam file')
    parser.add_argument('--min_frag_length', 
                        type = int, 
                        required = True, 
                        help = 'Minimum fragment length to consider')
    parser.add_argument('--max_frag_length', 
                        type = int, 
                        required = True, 
                        help = 'Maximum  fragment length to consider')
    parser.add_argument('--gzipbed', 
                        type = bool, 
                        required = False, 
                        default = True,
                        help = 'Gzip the output bed file or not. Default is True')
    parser.add_argument('--sort_by_readID', 
                        type = bool, 
                        required = False, 
                        default = False,
                        help = 'Sort the bed file by read ID. Default is False')
    parser.add_argument('--sampleid', 
                        type = str, 
                        required = True, 
                        help = 'SampleID')
    parser.add_argument('--rerun', action='store_true', help="Rerun the analysis or not")
    
    args = parser.parse_args()
    inputbam = args.inputbam
    outputdir = args.outputdir
    mapq = args.mapq
    region = args.region
    min_frag_length = args.min_frag_length
    max_frag_length = args.max_frag_length
    gzipbed = args.gzipbed
    rerun = args.rerun
    sort_by_readID = args.sort_by_readID
    # sampleid = inputbam.split("/")[-1].replace(".bam", "")
    sampleid = args.sampleid
    savename = f"{sampleid}_region_{region.replace(':', '_').replace('-', '_')}_fraglen_{min_frag_length}_{max_frag_length}"    

    bamfile = pysam.AlignmentFile(inputbam, 'rb')
    
    print("------------------------------------------------------------")
    print("List of input arguments: ")
    print(f"Input BAM file: {inputbam}")
    print(f"Output directory: {outputdir}")
    print(f"Minimum mapping quality: {mapq}")
    print(f"Region string: {region}")
    print(f"Minimum fragment length: {min_frag_length}")
    print(f"Maximum fragment length: {max_frag_length}")
    print(f"Extracted sample ID from the input bam file: {savename}")
    print(f"Name of the output file: {savename}")
    print(f"Rerun: {rerun}")
    print(f"sort_by_readID: {sort_by_readID}")
    print("------------------------------------------------------------")
    os.system(f"mkdir -p {outputdir}")

    bed_output_path = os.path.join(outputdir, f"{savename}.bed")
    if (os.path.isfile(bed_output_path.replace(".bed", ".sorted.bed.gz")) == False) or (rerun == True):
        if region.lower() != "full":
            print(f"Fetching reads from region: {region}")
            rp = read_pair_generator(bam = bamfile, region_string = region)
        else:
            print(f"Fetching reads from the full BAM file")
            rp = read_pair_generator(bam = bamfile)
        
        
        bedWrite = open(bed_output_path, "w")
        for read1, read2 in rp:
            read1Start = read1.reference_start
            read1End = read1.reference_end
            read2Start = read2.reference_start
            read2End = read2.reference_end
        
            if not read1.is_reverse:  # read1 is forward strand, read2 is reverse strand
                rstart = read1Start  # 0-based left-most site
                rend = read2End
            else:  # read1 is reverse strand, read2 is forward strand
                rstart = read2Start  # 0-based left-most site
                rend = read1End
        
            if (rstart < 0) or (rend < 0) or (rstart >= rend):
                continue
        
            read1dict = read1.to_dict()
            read2dict = read2.to_dict()
            if read1dict["ref_name"] != read2dict["ref_name"]:
                continue
        
            if (read1.mapq >= mapq) and (read2.mapq >= mapq):
                flen = rend - rstart
                if (min_frag_length is not None) and (max_frag_length is not None):
                    if (flen >= min_frag_length) and (flen <= max_frag_length) and (rstart > 5):
                        tmp_str = read1dict['ref_name'] + '\t' + str(rstart) + '\t' + str(rend) + '\t' + read1dict['name'] + '\t' + str(flen) + '\n'
                        bedWrite.write(tmp_str)
                else:
                    tmp_str = read1dict['ref_name'] + '\t' + str(rstart) + '\t' + str(rend) + '\t' + read1dict['name'] + '\t' + str(flen) + '\n'
                    bedWrite.write(tmp_str)
            else:
                continue
        bedWrite.close()
        if gzipbed:
            # gzip, generate index and remove redundant files. 
            if sort_by_readID:
                print("***** ***** ***** ***** *****")
                print("Sorting the BAM-converted BED file by READ ID.")
                print("***** ***** ***** ***** *****")
                os.system(f"sort -k4,4 {bed_output_path} > {bed_output_path.replace('.bed', '.sorted.bed')}")
            else:
                bedData = pybedtools.BedTool(bed_output_path)
                bedData.sort(output=bed_output_path.replace(".bed", ".sorted.bed"))
                pysam.tabix_compress(bed_output_path.replace(".bed", ".sorted.bed"), 
                                     bed_output_path.replace(".bed", ".sorted.bed.gz"), 
                                     force = rerun)
                pysam.tabix_index(bed_output_path.replace(".bed", ".sorted.bed.gz"), 
                                  preset = "bed", 
                                  zerobased = True,
                                 force = rerun)
                os.remove(bed_output_path.replace(".bed", ".sorted.bed"))
            # os.remove(bed_output_path) # do not remove the .bed file yet, need it for some other processes. 
        print(f"Finished converting input BAM file to BED file at {bed_output_path.replace('.bed', '.sorted.bed.gz') if gzipbed else bed_output_path}")
    else:
        print("Processed bed file exists.")
        
if __name__ == '__main__':
    main()