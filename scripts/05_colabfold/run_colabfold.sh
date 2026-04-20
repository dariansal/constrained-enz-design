#!/usr/bin/env bash
#SBATCH --job-name=cf_ENZ_REGIME
#SBATCH --output=/hpc/group/naderilab/darian/Enz/slurm/logs/cf_ENZ_REGIME_%j.out
#SBATCH --error=/hpc/group/naderilab/darian/Enz/slurm/logs/cf_ENZ_REGIME_%j.err
#SBATCH --account=scavenger-h200
#SBATCH --partition=scavenger-h200
#SBATCH --gres=gpu:h200_1g.18gb:1  # upgrade to h200_3g.71gb if OOM (AF2 at 150 AA peaks ~14 GB)
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH --time=1-00:00:00
# =============================================================================
# run_colabfold.sh
# Runs LocalColabFold (AlphaFold2) on all sequences from one experiment.
#
# To capture structural variance we:
#   --num-models 5      : run all 5 AlphaFold2 model weights
#   --num-recycle 3     : 3 recycles (fast but accurate)
#   --num-seeds 1       : use seed 0 (reproducible)
#
# Output: PDB files with pLDDT in B-factor column.
#   results/colabfold/ENZ_REGIME/
# =============================================================================

set -euo pipefail

ENZ="ENZ"
REGIME="REGIME"

PROJECT=/hpc/group/naderilab/darian/Enz
COLABFOLD_BIN=${PROJECT}/tools/localcolabfold/colabfold-conda/bin
WEIGHTS_DIR=${PROJECT}/tools/localcolabfold/colabfold
MPNN_OUT=${PROJECT}/results/proteinmpnn/${ENZ}_${REGIME}
OUT_DIR=${PROJECT}/results/colabfold/${ENZ}_${REGIME}

mkdir -p "${OUT_DIR}"

source /opt/apps/rhel9/Anaconda3-2024.02/etc/profile.d/conda.sh

echo "[$(date)] Starting ColabFold: ${ENZ}_${REGIME}"
echo "  GPU: $(nvidia-smi --query-gpu=name --format=csv,noheader)"

FASTA="${MPNN_OUT}/${ENZ}_${REGIME}_all_seqs.fasta"
if [ ! -f "${FASTA}" ]; then
    echo "ERROR: ${FASTA} not found. Run ProteinMPNN first."
    exit 1
fi

N_SEQS=$(grep -c ">" "${FASTA}")
echo "  Input: ${FASTA} (${N_SEQS} sequences)"

# -----------------------------------------------------------------------
# ColabFold batch prediction
#
# --num-models 5         : use all 5 AlphaFold2 model weights → structural variance
# --num-recycle 3        : number of recycling iterations
# --use-gpu-relax        : GPU-accelerated Amber relaxation
# --model-type alphafold2_ptm : gives per-residue pLDDT + pTM
# --rank auto            : rank by pTM+pLDDT
# --data ${WEIGHTS_DIR}  : path to downloaded params
#
# Note: ColabFold uses MMseqs2 API for MSA generation (remote).
# If the cluster has no internet access, add --msa-only after a pre-search.
# -----------------------------------------------------------------------
"${COLABFOLD_BIN}/colabfold_batch" \
    "${FASTA}" \
    "${OUT_DIR}" \
    --num-models 5 \
    --num-recycle 3 \
    --use-gpu-relax \
    --model-type alphafold2_ptm \
    --msa-mode single_sequence \
    --rank auto \
    --stop-at-score 70 \
    --data "${WEIGHTS_DIR}"

echo "[$(date)] ColabFold complete."
echo "  Output: ${OUT_DIR}/"

# -----------------------------------------------------------------------
# Verify output: count predicted PDB files
# -----------------------------------------------------------------------
N_PRED=$(find "${OUT_DIR}" -name "*.pdb" | wc -l)
echo "  Generated ${N_PRED} PDB files."

echo "${ENZ}_${REGIME} $(date)" >> "${PROJECT}/results/colabfold/.completed"
