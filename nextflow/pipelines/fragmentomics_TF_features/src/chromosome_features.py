import pandas as pd 
import pathlib
import os 
import numpy as np
import argparse
import sys
# path to the split chroms data


# inputdir="/Users/hieunguyen/outdir/ecd_wgs_and_enriched_features/ABC123_splitChroms";
# outputdir="/Users/hieunguyen/outdir/ecd_wgs_and_enriched_features/ABC123_splitChroms";
# python chromosome_features.py --input ${inputdir} --output ${outputdir}

def main():
    """
    Process chromosome fragment length data and compute statistical metrics.
    Reads fragment length files from an input directory, filters fragments by length (50-350 bp),
    and calculates average length, standard deviation, and Shannon entropy for each chromosome.
    Results are written to a TSV file in the output directory.
    Command-line Arguments:
        --input (str): Path to the input directory containing split chromosome data files (*.flen.txt).
                       Required.
        --output (str): Path to the output directory where results will be saved.
                        Required.
    Returns:
        None. Writes output TSV file containing columns: chrom, shannon, std, avgFlen.
    Raises:
        FileNotFoundError: If the input directory does not exist.
        argparse.ArgumentTypeError: If required arguments are missing.
    Notes:
        - Input files should follow naming convention: {chrom_name}.flen.txt
        - Fragment lengths are converted to absolute values before processing
        - Fragments outside the 50-350 bp range are filtered out
        - Shannon entropy is normalized by log2(301) where 301 = (350 - 50 + 1)
    """
    parser = argparse.ArgumentParser()
    parser.add_argument('--input', 
                        type = str, 
                        required = True, 
                        help = 'Path to the input split chroms data')
    parser.add_argument('--output', 
                        type = str, 
                        required = True, 
                        help = 'Output directory to save results')
    parser.add_argument('--sampleid', 
                        type = str, 
                        required = True, 
                        help = 'SampleID of the input data')
    args = parser.parse_args()
    inputdir = args.input
    outputdir = args.output
    sampleid = args.sampleid
    
    inputs = [item for item in pathlib.Path(inputdir).glob("*.flen.txt")]
    fulldf = pd.DataFrame()
    
    for inputfile in inputs:
        chrom = inputfile.name.split(".flen")[0]
        tmpdf = pd.read_csv(inputfile, header = None)
        tmpdf.columns = ["flen"]
        tmpdf["flen"] = tmpdf["flen"].abs()
        tmpdf = tmpdf[(tmpdf["flen"] >= 50) & (tmpdf["flen"] <= 350)]
        avg_flen = tmpdf.flen.mean()
        
        tmp_lendf = pd.DataFrame.from_dict(
            {
                "chrom" : chrom,
                "avgFlen" : avg_flen
            }, orient = "index"
        ).T
    
        std_lendf = pd.DataFrame.from_dict(
            {
                "chrom" : chrom,
                "std" : tmpdf.flen.std()
            }, orient = "index"
        ).T
        
        tmpdf["count"] = 1
        tmp_flendf = tmpdf.groupby("flen")["count"].sum().reset_index()
        tmp_flendf["pct"] = tmp_flendf["count"]/tmp_flendf["count"].sum()
        
        shannon_entropy = -np.sum([i * np.log2(i) for i in tmp_flendf.pct.values if i != 0])/np.log2(350 - 50 + 1)
        entropy_lendf = pd.DataFrame.from_dict(
            {
                "chrom" : chrom,
                "shannon" : shannon_entropy
            }, orient = "index"
        ).T
        mergedf = entropy_lendf.merge(std_lendf, right_on = "chrom", left_on = "chrom").merge(tmp_lendf, right_on = "chrom", left_on = "chrom")
        fulldf = pd.concat([fulldf, mergedf], axis = 0)
    
    fulldf.to_csv(os.path.join(outputdir, f"{sampleid}_std_avg_shannon.tsv"), sep = "\t", index = False)

if __name__ == '__main__':
    main()