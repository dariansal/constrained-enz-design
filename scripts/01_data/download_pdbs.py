#!/usr/bin/env python3
"""
download_pdbs.py
Downloads PDB structures for both enzyme systems and prepares clean single-chain files.

NOTE: PDB 1PPF is Human Leukocyte Elastase (HLE) + OMTKY3 inhibitor complex,
      NOT subtilisin. HLE is still a canonical Ser-His-Asp serine protease.
      Catalytic triad (geometrically confirmed): His57, Asp102, Ser195 (chain E).

Targets:
  1PPF — Human Leukocyte Elastase (chain E), serine protease Ser-His-Asp triad
  1CA2 — Human Carbonic Anhydrase II (chain A), Zn²⁺-binding His triad

Output:
  data/pdb/1ppf_raw.pdb
  data/pdb/1ppf_chainE.pdb     — chain E only, original numbering
  data/pdb/1ca2_raw.pdb
  data/pdb/1ca2_chainA.pdb     — chain A + ZN HETATM, original numbering

Usage:
  python scripts/01_data/download_pdbs.py
"""

import logging
import requests
from pathlib import Path

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s",
                    datefmt="%H:%M:%S")
log = logging.getLogger(__name__)

PROJECT = Path("/hpc/group/naderilab/darian/Enz")
PDB_DIR = PROJECT / "data" / "pdb"
PDB_DIR.mkdir(parents=True, exist_ok=True)


def download_pdb(pdb_id: str) -> Path:
    out = PDB_DIR / f"{pdb_id.lower()}_raw.pdb"
    if out.exists():
        log.info(f"  {pdb_id} already downloaded: {out}")
        return out
    url = f"https://files.rcsb.org/download/{pdb_id.upper()}.pdb"
    log.info(f"  Downloading {pdb_id} from RCSB...")
    r = requests.get(url, timeout=60)
    r.raise_for_status()
    out.write_text(r.text)
    log.info(f"  Saved: {out} ({out.stat().st_size // 1024} KB)")
    return out


def extract_chain(raw_pdb: Path, chain: str, out_path: Path,
                  keep_hetatm_names: tuple[str, ...] = ()) -> Path:
    """
    Extract one chain from a PDB file with ORIGINAL residue numbering.
    Only keeps HETATM records whose residue name is in keep_hetatm_names.
    """
    if out_path.exists():
        log.info(f"  {out_path.name} already exists — skipping.")
        return out_path

    lines_out = []
    for line in raw_pdb.read_text().splitlines(keepends=True):
        rec = line[:6].strip()
        if rec == "ATOM" and line[21] == chain:
            lines_out.append(line)
        elif rec == "HETATM" and line[21] == chain:
            rname = line[17:20].strip()
            if rname in keep_hetatm_names:
                lines_out.append(line)
    lines_out.append("END\n")

    if len(lines_out) <= 1:
        raise ValueError(f"No atoms found for chain '{chain}' in {raw_pdb}")

    out_path.write_text("".join(lines_out))
    log.info(f"  Extracted chain {chain} → {out_path.name} ({len(lines_out)} records)")
    return out_path


def verify_catalytic(pdb_path: Path, chain: str,
                     residues: list[int], expected_names: list[str]) -> bool:
    found = {}
    for line in pdb_path.read_text().splitlines():
        if line[:4] not in ("ATOM", "HET"):
            continue
        if line[21] != chain:
            continue
        rn = int(line[22:26])
        rname = line[17:20].strip()
        found.setdefault(rn, rname)

    all_ok = True
    for rn, exp in zip(residues, expected_names):
        actual = found.get(rn, "NOT FOUND")
        ok = actual == exp
        log.info(f"    Res {rn}: expected={exp}, actual={actual} "
                 f"[{'OK' if ok else 'MISMATCH'}]")
        if not ok:
            all_ok = False
    return all_ok


def main():
    log.info("=== Downloading and preparing PDB structures ===")

    # -----------------------------------------------------------------------
    # 1PPF — Human Leukocyte Elastase (HLE) / OMTKY3 complex
    #   Chain E = HLE (serine protease, chymotrypsin family)
    #   Catalytic triad (geometrically verified):
    #     His57 (general base), Asp102 (charge relay), Ser195 (nucleophile)
    # -----------------------------------------------------------------------
    log.info("\n--- 1PPF (Human Leukocyte Elastase, chain E) ---")
    raw = download_pdb("1PPF")
    extract_chain(raw, "E", PDB_DIR / "1ppf_chainE.pdb")
    log.info("  Verifying catalytic triad (His57, Asp102, Ser195):")
    ok = verify_catalytic(PDB_DIR / "1ppf_chainE.pdb", "E",
                          [57, 102, 195], ["HIS", "ASP", "SER"])
    if not ok:
        log.warning("  Some catalytic residues mismatched — check the PDB file!")
    else:
        log.info("  All catalytic residues verified ✓")

    # -----------------------------------------------------------------------
    # 1CA2 — Human Carbonic Anhydrase II
    #   Chain A = enzyme (259 residues)
    #   Zn-binding triad (geometrically verified, ~2.0 A to ZN):
    #     His94, His96, His119 (coordinate Zn²⁺ at residue 262)
    # -----------------------------------------------------------------------
    log.info("\n--- 1CA2 (Human Carbonic Anhydrase II, chain A) ---")
    raw = download_pdb("1CA2")
    extract_chain(raw, "A", PDB_DIR / "1ca2_chainA.pdb",
                  keep_hetatm_names=("ZN",))   # keep the structural Zn
    log.info("  Verifying Zn-binding triad (His94, His96, His119):")
    ok = verify_catalytic(PDB_DIR / "1ca2_chainA.pdb", "A",
                          [94, 96, 119], ["HIS", "HIS", "HIS"])
    if not ok:
        log.warning("  Some catalytic residues mismatched — check the PDB file!")
    else:
        log.info("  All catalytic residues verified ✓")

    log.info("\n=== PDB files ready ===")
    for f in sorted(PDB_DIR.glob("*.pdb")):
        if "chain" in f.name:
            log.info(f"  {f}")
    log.info("\nNext: python scripts/02_motifs/extract_motifs.py")


if __name__ == "__main__":
    main()
