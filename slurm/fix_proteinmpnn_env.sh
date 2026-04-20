#!/usr/bin/env bash
#SBATCH --job-name=fix_mpnn_env
#SBATCH --output=/hpc/group/naderilab/darian/Enz/slurm/logs/fix_mpnn_env_%j.out
#SBATCH --error=/hpc/group/naderilab/darian/Enz/slurm/logs/fix_mpnn_env_%j.err
#SBATCH --partition=scavenger-h200
#SBATCH --account=scavenger-h200
#SBATCH --gres=gpu:h200_1g.18gb:1
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=0:30:00

set -euo pipefail

ENV=/hpc/group/naderilab/darian/conda_environments/enz_proteinmpnn
CACHE_DIR=/hpc/group/naderilab/darian/pkg_cache

export PIP_CACHE_DIR="${CACHE_DIR}/pip"
export XDG_CACHE_HOME="${CACHE_DIR}/xdg"
mkdir -p "${PIP_CACHE_DIR}" "${XDG_CACHE_HOME}"

PIP="${ENV}/bin/pip"

echo "[$(date)] GPU: $(nvidia-smi --query-gpu=name --format=csv,noheader)"

echo "[$(date)] Step 1: Fix missing typing_extensions..."
"${PIP}" install typing_extensions

echo "[$(date)] Step 2: Downgrade numpy to 1.x..."
"${PIP}" install "numpy<2.0" --upgrade

echo "[$(date)] Step 3: Reinstall PyTorch 2.1.2 with CUDA 12.1..."
"${PIP}" uninstall -y torch torchvision torchaudio 2>/dev/null || true
"${PIP}" install torch==2.1.2 torchvision==0.16.2 torchaudio==2.1.2 \
    --index-url https://download.pytorch.org/whl/cu121

echo "[$(date)] Verifying..."
"${ENV}/bin/python" -c "
import torch
print('torch', torch.__version__)
print('CUDA available:', torch.cuda.is_available())
print('GPU:', torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'none')
import numpy; print('numpy', numpy.__version__)
"

echo "[$(date)] enz_proteinmpnn env fixed for CUDA 12 / H200."
