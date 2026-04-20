#!/usr/bin/env bash
#SBATCH --job-name=mpnn_1ca2_shell5
#SBATCH --output=/hpc/group/naderilab/darian/Enz/slurm/logs/mpnn_1ca2_shell5_%j.out
#SBATCH --error=/hpc/group/naderilab/darian/Enz/slurm/logs/mpnn_1ca2_shell5_%j.err
#SBATCH --account=scavenger-h200
#SBATCH --partition=scavenger-h200
#SBATCH --gres=gpu:h200_1g.18gb:1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=1-00:00:00
# =============================================================================
# run_proteinmpnn.sh
# Designs sequences for all RFdiffusion-generated backbones in one experiment.
#
# For each backbone PDB, runs ProteinMPNN and samples N_SEQ_PER_DESIGN sequences.
# Output FASTA files go to results/proteinmpnn/1ca2_shell5/
# =============================================================================

set -euo pipefail

ENZ="1ca2"
REGIME="shell5"
N_SEQ_PER_DESIGN=5
TEMPERATURE=0.1       # lower T → more deterministic sequences (higher confidence)

PROJECT=/hpc/group/naderilab/darian/Enz
ENV=/hpc/group/naderilab/darian/conda_environments/enz_proteinmpnn
MPNN=${PROJECT}/tools/ProteinMPNN
RFDIFF_OUT=${PROJECT}/results/rfdiffusion/${ENZ}_${REGIME}
OUT_DIR=${PROJECT}/results/proteinmpnn/${ENZ}_${REGIME}

mkdir -p "${OUT_DIR}"/{backbones,seqs,parsed_pdbs}

source /opt/apps/rhel9/Anaconda3-2024.02/etc/profile.d/conda.sh
export LD_LIBRARY_PATH=/opt/apps/rhel9/cuda-12.4/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
conda activate "${ENV}"

echo "[$(date)] Starting ProteinMPNN: ${ENZ}_${REGIME}"
echo "  Input:  ${RFDIFF_OUT}/"
echo "  Output: ${OUT_DIR}/"

# -----------------------------------------------------------------------
# Step 1: parse_multiple_chains.py
# Converts PDB files to a JSON format ProteinMPNN understands.
# -----------------------------------------------------------------------
BACKBONE_LIST="${OUT_DIR}/backbone_list.txt"
ls "${RFDIFF_OUT}/"design_*.pdb > "${BACKBONE_LIST}" 2>/dev/null || {
    echo "ERROR: No design_*.pdb files found in ${RFDIFF_OUT}/"
    exit 1
}
N_BACKBONES=$(wc -l < "${BACKBONE_LIST}")
echo "  Found ${N_BACKBONES} backbone PDB files."

python "${MPNN}/helper_scripts/parse_multiple_chains.py" \
    --input_path="${RFDIFF_OUT}" \
    --output_path="${OUT_DIR}/parsed_pdbs/parsed.jsonl"

# -----------------------------------------------------------------------
# Step 2: assign_fixed_chains.py (optional but good practice)
# Here we don't fix any chain — the entire backbone is designable.
# -----------------------------------------------------------------------

# -----------------------------------------------------------------------
# Step 3: protein_mpnn_run.py
# Core sequence design step.
#
# Key parameters:
#   --num_seq_per_target  : sequences to sample per backbone
#   --sampling_temp       : 0.1 = near-greedy, 1.0 = maximum diversity
#   --seed                : for reproducibility
# -----------------------------------------------------------------------
python "${MPNN}/protein_mpnn_run.py" \
    --jsonl_path "${OUT_DIR}/parsed_pdbs/parsed.jsonl" \
    --out_folder "${OUT_DIR}" \
    --path_to_model_weights "${MPNN}/vanilla_model_weights" \
    --num_seq_per_target ${N_SEQ_PER_DESIGN} \
    --sampling_temp ${TEMPERATURE} \
    --seed 42 \
    --batch_size 1

echo "[$(date)] ProteinMPNN complete."
echo "  FASTA files: ${OUT_DIR}/seqs/"
ls "${OUT_DIR}/seqs/"*.fa 2>/dev/null | head -3

# -----------------------------------------------------------------------
# Step 4: consolidate FASTAs for ColabFold
# ColabFold expects one FASTA with unique sequence IDs.
# -----------------------------------------------------------------------
CONSOLIDATED="${OUT_DIR}/${ENZ}_${REGIME}_all_seqs.fasta"
export OUT_DIR ENZ REGIME   # make shell vars visible to the Python subprocess
python - <<'PYEOF'
import os, glob, re
from pathlib import Path

out_dir = os.environ["OUT_DIR"]
enz     = os.environ["ENZ"]
regime  = os.environ["REGIME"]
consolidated = f"{out_dir}/{enz}_{regime}_all_seqs.fasta"

seqs = {}
for fa_file in sorted(glob.glob(f"{out_dir}/seqs/*.fa")):
    design_id = Path(fa_file).stem
    with open(fa_file) as f:
        seq_id = None
        for line in f:
            line = line.strip()
            if line.startswith(">"):
                sample_match = re.search(r"sample=(\d+)", line)
                if sample_match:
                    seq_id = f"{design_id}_s{sample_match.group(1)}"
                else:
                    seq_id = None  # skip native reconstruction
            elif seq_id and line:
                seqs[seq_id] = line
                seq_id = None

with open(consolidated, "w") as f:
    for sid, seq in seqs.items():
        f.write(f">{sid}\n{seq}\n")

print(f"Consolidated {len(seqs)} sequences → {consolidated}")
PYEOF

echo "  Consolidated FASTA: ${CONSOLIDATED}"
echo "${ENZ}_${REGIME} $(date)" >> "${PROJECT}/results/proteinmpnn/.completed"
