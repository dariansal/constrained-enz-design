#!/usr/bin/env python3
"""
extract_motifs.py

For each enzyme, this script:
  1. Loads the cleaned single-chain PDB.
  2. Identifies the catalytic residues.
  3. Computes three coordination shells:
       - motif_only:  just the catalytic residues
       - shell5:      catalytic residues + all residues within 5 Å
       - shell8:      catalytic residues + all residues within 8 Å
  4. For each shell, writes:
       - A motif PDB file (atoms from the fixed residues only)
       - A contig string for RFdiffusion
       - A JSON file with metadata (residue lists, RMSD reference atoms)
  5. Writes configs/experiments.yaml describing all 6 experiments.

Output:
  data/motifs/1ppf_{motif_only,shell5,shell8}/
    motif.pdb
    contig.txt
    metadata.json
  data/motifs/1ca2_{motif_only,shell5,shell8}/
    ...
  configs/experiments.yaml

Usage:
  conda run -p /hpc/group/naderilab/darian/conda_environments/enz_analysis \
      python scripts/02_motifs/extract_motifs.py
"""

import json
import logging
import os
from collections import defaultdict
from itertools import groupby
from pathlib import Path
from typing import NamedTuple

import numpy as np
import yaml

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger(__name__)

PROJECT  = Path("/hpc/group/naderilab/darian/Enz")
PDB_DIR  = PROJECT / "data" / "pdb"
MOTIF_DIR = PROJECT / "data" / "motifs"
CONFIG_DIR = PROJECT / "configs"

MOTIF_DIR.mkdir(parents=True, exist_ok=True)
CONFIG_DIR.mkdir(parents=True, exist_ok=True)

# ---------------------------------------------------------------------------
# Data structures
# ---------------------------------------------------------------------------

class Atom(NamedTuple):
    record: str    # "ATOM" or "HETATM"
    serial: int
    name: str
    altloc: str
    resname: str
    chain: str
    resseq: int
    icode: str
    x: float
    y: float
    z: float
    occupancy: float
    bfactor: float
    element: str
    line: str      # original line

# ---------------------------------------------------------------------------
# PDB parsing (no BioPython dependency for portability)
# ---------------------------------------------------------------------------

def parse_pdb(pdb_path: Path) -> list[Atom]:
    atoms = []
    for line in pdb_path.read_text().splitlines():
        rec = line[:6].strip()
        if rec not in ("ATOM", "HETATM"):
            continue
        try:
            a = Atom(
                record=rec,
                serial=int(line[6:11]),
                name=line[12:16].strip(),
                altloc=line[16].strip(),
                resname=line[17:20].strip(),
                chain=line[21],
                resseq=int(line[22:26]),
                icode=line[26].strip(),
                x=float(line[30:38]),
                y=float(line[38:46]),
                z=float(line[46:54]),
                occupancy=float(line[54:60]) if line[54:60].strip() else 1.0,
                bfactor=float(line[60:66]) if line[60:66].strip() else 0.0,
                element=line[76:78].strip() if len(line) > 76 else "",
                line=line,
            )
            atoms.append(a)
        except (ValueError, IndexError):
            continue
    return atoms


def atoms_by_residue(atoms: list[Atom]) -> dict[int, list[Atom]]:
    """Group atoms by residue sequence number."""
    res = defaultdict(list)
    for a in atoms:
        res[a.resseq].append(a)
    return dict(res)


def ca_coords(atoms: list[Atom]) -> dict[int, np.ndarray]:
    """Return C-alpha coordinates keyed by residue number."""
    ca = {}
    for a in atoms:
        if a.name == "CA" and a.record == "ATOM":
            ca[a.resseq] = np.array([a.x, a.y, a.z])
    return ca


def all_heavy_coords(atoms: list[Atom]) -> dict[int, np.ndarray]:
    """Return all heavy-atom coordinates keyed by (resseq, name)."""
    coords = {}
    for a in atoms:
        if a.record == "ATOM" and a.element != "H":
            coords[(a.resseq, a.name)] = np.array([a.x, a.y, a.z])
    return coords


# ---------------------------------------------------------------------------
# Shell computation
# ---------------------------------------------------------------------------

def find_shell_residues(
    atoms: list[Atom],
    catalytic_resnums: list[int],
    cutoff: float,
) -> list[int]:
    """
    Find all residue numbers (ATOM records only) whose heavy atoms come
    within `cutoff` Å of any heavy atom of the catalytic residues.
    Returns sorted list including catalytic residues themselves.
    """
    cat_coords = []
    for a in atoms:
        if a.record == "ATOM" and a.resseq in catalytic_resnums and a.element != "H":
            cat_coords.append(np.array([a.x, a.y, a.z]))

    if not cat_coords:
        raise ValueError(f"No ATOM records found for residues {catalytic_resnums}")

    cat_arr = np.array(cat_coords)  # (N_cat, 3)

    shell = set(catalytic_resnums)
    residue_groups = atoms_by_residue(atoms)

    for resnum, res_atoms in residue_groups.items():
        heavy = [np.array([a.x, a.y, a.z]) for a in res_atoms
                 if a.record == "ATOM" and a.element != "H"]
        if not heavy:
            continue
        heavy_arr = np.array(heavy)  # (N_res, 3)
        # Vectorised distance: (N_res, N_cat)
        diffs = heavy_arr[:, None, :] - cat_arr[None, :, :]
        dists = np.linalg.norm(diffs, axis=-1)  # (N_res, N_cat)
        if dists.min() <= cutoff:
            shell.add(resnum)

    return sorted(shell)


# ---------------------------------------------------------------------------
# Contiguous segment grouping → RFdiffusion contig format
# ---------------------------------------------------------------------------

def residues_to_segments(residues: list[int]) -> list[tuple[int, int]]:
    """
    Convert a sorted list of residue numbers into contiguous segments.
    E.g. [30,31,32,64,65,221] → [(30,32),(64,65),(221,221)]
    """
    segments = []
    for k, g in groupby(enumerate(residues), lambda x: x[1] - x[0]):
        group = list(g)
        segments.append((group[0][1], group[-1][1]))
    return segments


def build_contig_string(
    chain: str,
    fixed_segments: list[tuple[int, int]],
    n_designs_length: int = 150,
    min_gap: int = 5,
    max_gap: int = 30,
) -> str:
    """
    Build an RFdiffusion contig string.

    The total designed length targets approximately `n_designs_length` AA.
    The fixed segments are interleaved with variable-length regions.

    Format example:
        '[10/A30-32/20/A64-65/20/A221-221/15]'

    The numbers represent variable-length regions to generate.
    The chain-prefixed ranges are fixed scaffold segments.

    Strategy:
      - Start with a random N-terminal tail
      - Between each pair of fixed segments: insert a variable region
      - End with a C-terminal tail
      - Total fixed + variable ≈ n_designs_length
    """
    n_fixed = sum(e - s + 1 for s, e in fixed_segments)
    n_variable = n_designs_length - n_fixed

    # Distribute variable residues across gaps
    # Gaps: n_segments+1 positions (before first, between each pair, after last)
    n_gaps = len(fixed_segments) + 1
    per_gap = max(min_gap, n_variable // n_gaps)

    # Build contig parts
    parts = []
    # N-terminal unstructured region
    n_term = max(min_gap, per_gap)
    parts.append(f"{n_term}")

    for i, (start, end) in enumerate(fixed_segments):
        parts.append(f"{chain}{start}-{end}")
        if i < len(fixed_segments) - 1:
            gap = max(min_gap, per_gap)
            parts.append(f"{gap}")

    # C-terminal
    c_term = max(min_gap, per_gap)
    parts.append(f"{c_term}")

    contig = "[" + "/".join(parts) + "]"
    return contig


def build_loose_contig(
    chain: str,
    catalytic_resnums: list[int],
    n_designs_length: int = 150,
) -> str:
    """
    When fixing only individual scattered residues, each gets its own 1-residue
    segment with generous gaps between them. This is the 'motif_only' regime.
    """
    n_fixed = len(catalytic_resnums)
    n_variable = n_designs_length - n_fixed
    n_gaps = n_fixed + 1
    per_gap = max(10, n_variable // n_gaps)

    parts = [str(per_gap)]
    for i, rn in enumerate(catalytic_resnums):
        parts.append(f"{chain}{rn}-{rn}")
        if i < n_fixed - 1:
            parts.append(str(per_gap))
    # C-terminal
    remaining = n_designs_length - (per_gap * (n_gaps - 1)) - n_fixed
    parts.append(str(max(5, remaining)))

    return "[" + "/".join(parts) + "]"


# ---------------------------------------------------------------------------
# Write motif PDB (atoms from fixed residues only)
# ---------------------------------------------------------------------------

def write_motif_pdb(
    atoms: list[Atom],
    fixed_resnums: list[int],
    out_path: Path,
    chain: str,
) -> None:
    """Write a minimal PDB containing only the fixed residue atoms."""
    out_lines = []
    serial = 1
    for a in atoms:
        if a.resseq in fixed_resnums and a.record in ("ATOM", "HETATM"):
            # Rewrite with sequential serial numbers
            out_lines.append(
                f"{a.record:<6}{serial:5d} {a.name:<4}{a.altloc:1}"
                f"{a.resname:<3} {a.chain}{a.resseq:4d}{a.icode:1}   "
                f"{a.x:8.3f}{a.y:8.3f}{a.z:8.3f}"
                f"{a.occupancy:6.2f}{a.bfactor:6.2f}"
                f"          {a.element:>2}\n"
            )
            serial += 1
    out_lines.append("END\n")
    out_path.write_text("".join(out_lines))
    log.info(f"  Motif PDB: {out_path} ({serial-1} atoms)")


# ---------------------------------------------------------------------------
# Experiment definition
# ---------------------------------------------------------------------------

def define_experiment(
    enzyme_id: str,
    pdb_path: Path,
    chain: str,
    catalytic_resnums: list[int],
    catalytic_resnames: list[str],
    regime: str,           # "motif_only", "shell5", "shell8"
    cutoff: float | None,  # None for motif_only
    atoms: list[Atom],
    n_designs: int = 20,
    n_seq_per_design: int = 5,
    target_length: int = 150,
) -> dict:
    """Build one experiment's data and return metadata dict."""

    exp_name = f"{enzyme_id}_{regime}"
    out_dir = MOTIF_DIR / exp_name
    out_dir.mkdir(parents=True, exist_ok=True)

    if cutoff is None:
        fixed_resnums = catalytic_resnums
        contig = build_loose_contig(chain, catalytic_resnums, target_length)
        n_fixed = len(catalytic_resnums)
    else:
        fixed_resnums = find_shell_residues(atoms, catalytic_resnums, cutoff)
        segments = residues_to_segments(fixed_resnums)
        contig = build_contig_string(chain, segments, target_length)
        n_fixed = sum(e - s + 1 for s, e in segments)

    log.info(f"  [{exp_name}] {n_fixed} fixed residues, contig: {contig}")

    # Write motif PDB
    motif_pdb = out_dir / "motif.pdb"
    write_motif_pdb(atoms, fixed_resnums, motif_pdb, chain)

    # Write contig string
    (out_dir / "contig.txt").write_text(contig + "\n")

    # Compute reference catalytic atom positions (for RMSD calculation)
    ref_positions = {}
    ca_map = ca_coords(atoms)
    for rn, rname in zip(catalytic_resnums, catalytic_resnames):
        if rn in ca_map:
            ref_positions[f"{chain}{rn}_{rname}_CA"] = ca_map[rn].tolist()

    metadata = {
        "experiment_name": exp_name,
        "enzyme_id": enzyme_id,
        "regime": regime,
        "chain": chain,
        "pdb_file": str(pdb_path),
        "motif_pdb": str(motif_pdb),
        "catalytic_resnums": catalytic_resnums,
        "catalytic_resnames": catalytic_resnames,
        "fixed_resnums": fixed_resnums,
        "n_fixed_residues": n_fixed,
        "contig": contig,
        "target_length": target_length,
        "n_designs": n_designs,
        "n_seq_per_design": n_seq_per_design,
        "cutoff_angstroms": cutoff,
        "reference_ca_positions": ref_positions,
    }

    with open(out_dir / "metadata.json", "w") as f:
        json.dump(metadata, f, indent=2)
    log.info(f"  Metadata saved to {out_dir}/metadata.json")

    return metadata


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    log.info("=== Extracting catalytic motifs and building experiment configs ===")

    all_experiments = []

    # -----------------------------------------------------------------------
    # Enzyme 1: Human Leukocyte Elastase (1PPF, chain E)
    # NOTE: 1PPF is HLE (chymotrypsin family), NOT subtilisin.
    # Both are Ser-His-Asp serine proteases — the experiment is equivalent.
    # Catalytic triad (geometrically verified):
    #   His57 (general base), Asp102 (charge relay), Ser195 (nucleophile)
    # -----------------------------------------------------------------------
    log.info("\n--- Enzyme 1: Human Leukocyte Elastase (1PPF) ---")
    pdb_1ppf = PDB_DIR / "1ppf_chainE.pdb"
    if not pdb_1ppf.exists():
        log.error(f"{pdb_1ppf} not found. Run 01_data/download_pdbs.py first.")
        return

    atoms_1ppf = parse_pdb(pdb_1ppf)
    log.info(f"  Loaded {len(atoms_1ppf)} atoms from {pdb_1ppf.name}")

    for regime, cutoff in [("motif_only", None), ("shell5", 5.0), ("shell8", 8.0)]:
        meta = define_experiment(
            enzyme_id="1ppf",
            pdb_path=pdb_1ppf,
            chain="E",
            catalytic_resnums=[57, 102, 195],
            catalytic_resnames=["HIS", "ASP", "SER"],
            regime=regime,
            cutoff=cutoff,
            atoms=atoms_1ppf,
            n_designs=20,
            n_seq_per_design=5,
            target_length=150,
        )
        all_experiments.append(meta)

    # -----------------------------------------------------------------------
    # Enzyme 2: Carbonic Anhydrase II (1CA2, chain A)
    # Zinc-binding histidines: His94, His96, His119
    # -----------------------------------------------------------------------
    log.info("\n--- Enzyme 2: Carbonic Anhydrase II (1CA2) ---")
    pdb_1ca2 = PDB_DIR / "1ca2_chainA.pdb"
    if not pdb_1ca2.exists():
        log.error(f"{pdb_1ca2} not found. Run 01_data/download_pdbs.py first.")
        return

    atoms_1ca2 = parse_pdb(pdb_1ca2)
    log.info(f"  Loaded {len(atoms_1ca2)} atoms from {pdb_1ca2.name}")

    for regime, cutoff in [("motif_only", None), ("shell5", 5.0), ("shell8", 8.0)]:
        meta = define_experiment(
            enzyme_id="1ca2",
            pdb_path=pdb_1ca2,
            chain="A",
            catalytic_resnums=[94, 96, 119],   # Zn-binding His (verified: ~2.0 A to ZN)
            catalytic_resnames=["HIS", "HIS", "HIS"],
            regime=regime,
            cutoff=cutoff,
            atoms=atoms_1ca2,
            n_designs=20,
            n_seq_per_design=5,
            target_length=150,
        )
        all_experiments.append(meta)

    # -----------------------------------------------------------------------
    # Write experiments.yaml
    # -----------------------------------------------------------------------
    experiments_yaml = CONFIG_DIR / "experiments.yaml"
    with open(experiments_yaml, "w") as f:
        yaml.dump(
            {
                "experiments": [
                    {
                        k: v for k, v in exp.items()
                        if k != "reference_ca_positions"  # keep yaml readable
                    }
                    for exp in all_experiments
                ]
            },
            f,
            default_flow_style=False,
            sort_keys=False,
        )
    log.info(f"\nExperiment config written to {experiments_yaml}")

    # Summary table
    log.info("\n=== Experiment Summary ===")
    log.info(f"{'Experiment':<30} {'Fixed residues':>15} {'Contig'}")
    log.info("-" * 80)
    for exp in all_experiments:
        log.info(
            f"{exp['experiment_name']:<30} {exp['n_fixed_residues']:>15}     {exp['contig']}"
        )
    log.info("\nNext: submit SLURM jobs via scripts/03_rfdiffusion/submit_all.sh")


if __name__ == "__main__":
    main()
