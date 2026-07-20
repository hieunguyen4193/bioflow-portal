"""
Cell-cycle gene lists — the same canonical Tirosh et al. (2015) S-phase /
G2M-phase human gene sets that ship inside the Seurat package as `cc.genes`
(`cc.genes$s.genes`, `cc.genes$g2m.genes`). Kept here as a plain Python module
so every pipeline step imports the identical list, mirroring how the R
pipeline relies on Seurat's bundled `cc.genes` object.
"""

S_GENES = [
    "MCM5", "PCNA", "TYMS", "FEN1", "MCM2", "MCM4", "RRM1", "UNG", "GINS2",
    "MCM6", "CDCA7", "DTL", "PRIM1", "UHRF1", "MLF1IP", "HELLS", "RFC2",
    "RPA2", "NASP", "RAD51AP1", "GMNN", "WDR76", "SLBP", "CCNE2", "UBR7",
    "POLD3", "MSH2", "ATAD2", "RAD51", "RRM2", "CDC45", "CDC6", "EXO1",
    "TIPIN", "DSCC1", "BLM", "CASP8AP2", "USP1", "CLSPN", "POLA1", "CHAF1B",
    "BRIP1", "E2F8",
]

G2M_GENES = [
    "HMGB2", "CDK1", "NUSAP1", "UBE2C", "BIRC5", "TPX2", "TOP2A", "NDC80",
    "CKS2", "NUF2", "CKS1B", "MKI67", "TMPO", "CENPF", "TACC3", "FAM64A",
    "SMC4", "CCNB2", "CKAP2L", "CKAP2", "AURKB", "BUB1", "KIF11", "ANP32E",
    "TUBB4B", "GTSE1", "KIF20B", "HJURP", "CDCA3", "HN1", "CDC20", "TTK",
    "CDC25C", "KIF2C", "RANGAP1", "NCAPD2", "DLGAP5", "CDCA2", "CDCA8",
    "ECT2", "KIF23", "HMMR", "AURKA", "PSRC1", "ANLN", "LBR", "CKAP5",
    "CENPE", "CTCF", "NEK2", "G2E3", "GAS2L3", "CBX5", "CENPA",
]


def match_genes_case_insensitive(candidates, all_genes):
    """
    Mirror the R pattern:
      pattern <- paste0("^", cc.genes$s.genes, "$", collapse = "|")
      matched <- all.genes[grepl(pattern, all.genes, ignore.case = TRUE)]
    i.e. exact, case-insensitive matches against the dataset's gene symbols
    (handles mouse gene symbols like "Mcm5" transparently).
    """
    lookup = {g.upper(): g for g in all_genes}
    return [lookup[c.upper()] for c in candidates if c.upper() in lookup]
