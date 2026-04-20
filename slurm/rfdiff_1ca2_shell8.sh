#!/usr/bin/env bash
#SBATCH --job-name=rfdiff_1ca2_shell8
#SBATCH --output=/hpc/group/naderilab/darian/Enz/slurm/logs/rfdiff_1ca2_shell8_%j.out
#SBATCH --error=/hpc/group/naderilab/darian/Enz/slurm/logs/rfdiff_1ca2_shell8_%j.err
#SBATCH --account=scavenger-h200
#SBATCH --partition=scavenger-h200
#SBATCH --gres=gpu:h200_1g.18gb:1
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --time=1-00:00:00
#SBATCH --mail-type=END,FAIL
# =============================================================================
# run_rfdiffusion.sh
# Template SLURM script for one RFdiffusion experiment.
# Filled in by submit_all.sh; do not run directly.
#
# Generates N_DESIGNS backbone structures conditioned on the catalytic motif.
# Output: PDB files in results/rfdiffusion/1ca2_shell8/
# =============================================================================

set -euo pipefail

# ---------- Parameters (filled by submit_all.sh) ----------
ENZ="1ca2"               # enzyme id: 1ppf or 1ca2
REGIME="shell8"         # motif_only | shell5 | shell8
N_DESIGNS=20
# ----------------------------------------------------------

PROJECT=/hpc/group/naderilab/darian/Enz
ENV=/hpc/group/naderilab/darian/conda_environments/enz_rfdiffusion
RFDIFF=${PROJECT}/tools/RFdiffusion
WEIGHTS=${PROJECT}/weights/rfdiffusion
MOTIF_DIR=${PROJECT}/data/motifs/${ENZ}_${REGIME}
OUT_DIR=${PROJECT}/results/rfdiffusion/${ENZ}_${REGIME}

mkdir -p "${OUT_DIR}"

# Load conda and CUDA 12 runtime (required by DGL/torch cu121)
source /opt/apps/rhel9/Anaconda3-2024.02/etc/profile.d/conda.sh
export LD_LIBRARY_PATH=/opt/apps/rhel9/cuda-12.4/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
conda activate "${ENV}"

# Read contig string
CONTIG=$(cat "${MOTIF_DIR}/contig.txt")
echo "[$(date)] Starting RFdiffusion: ${ENZ}_${REGIME}"
echo "  Contig: ${CONTIG}"
echo "  GPU: $(nvidia-smi --query-gpu=name --format=csv,noheader)"

# -----------------------------------------------------------------------
# RFdiffusion inference
#
# Key parameters:
#   contigmap.contigs   : defines fixed motif and variable scaffold
#   inference.num_designs: number of backbones to generate
#   denoising.noise_scale_ca / .noise_scale_frame:
#       controls how aggressively new residues are sampled (leave at defaults)
#   potentials.guiding_potentials: optional energy-based guidance (off by default)
# -----------------------------------------------------------------------
python "${RFDIFF}/scripts/run_inference.py" \
    inference.input_pdb="${MOTIF_DIR}/motif.pdb" \
    inference.output_prefix="${OUT_DIR}/design" \
    inference.num_designs=${N_DESIGNS} \
    "contigmap.contigs=[${CONTIG:1:-1}]" \
    inference.ckpt_override_path="${WEIGHTS}/ActiveSite_ckpt.pt" \
    inference.write_trajectory=false

echo "[$(date)] RFdiffusion complete."
echo "  Output: ${OUT_DIR}/"
ls -lh "${OUT_DIR}/"*.pdb | head -5

# Write a completion marker
echo "${ENZ}_${REGIME} $(date)" >> "${PROJECT}/results/rfdiffusion/.completed"
