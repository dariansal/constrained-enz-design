#!/usr/bin/env bash
#SBATCH --job-name=fix_rfdiff_env
#SBATCH --output=/hpc/group/naderilab/darian/Enz/slurm/logs/fix_rfdiff_env_%j.out
#SBATCH --error=/hpc/group/naderilab/darian/Enz/slurm/logs/fix_rfdiff_env_%j.err
#SBATCH --partition=scavenger-h200
#SBATCH --account=scavenger-h200
#SBATCH --gres=gpu:h200_1g.18gb:1
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --time=1:00:00
# Fixes the enz_rfdiffusion env for H200 (CUDA 12) nodes:
#   1. Downgrades numpy to <2 (binary compat with compiled extensions)
#   2. Reinstalls torch with CUDA 12.1 support
#   3. Reinstalls DGL for torch-2.1 + CUDA 12.1
#   4. Reinstalls se3-transformer (recompiles against new torch/CUDA)

set -euo pipefail

ENV=/hpc/group/naderilab/darian/conda_environments/enz_rfdiffusion
PROJECT=/hpc/group/naderilab/darian/Enz
CACHE_DIR=/hpc/group/naderilab/darian/pkg_cache

export PIP_CACHE_DIR="${CACHE_DIR}/pip"
export XDG_CACHE_HOME="${CACHE_DIR}/xdg"
mkdir -p "${PIP_CACHE_DIR}" "${XDG_CACHE_HOME}"

source /opt/apps/rhel9/Anaconda3-2024.02/etc/profile.d/conda.sh
export LD_LIBRARY_PATH=/opt/apps/rhel9/cuda-12.4/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
PIP="${ENV}/bin/pip"

echo "[$(date)] Confirming GPU and CUDA..."
nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader
echo ""

echo "[$(date)] Step 1: Downgrade numpy to 1.x..."
"${PIP}" install "numpy<2.0" --upgrade

echo "[$(date)] Step 2: Remove old CUDA 11.8 torch and DGL..."
"${PIP}" uninstall -y torch torchvision torchaudio dgl 2>/dev/null || true

echo "[$(date)] Step 3: Install PyTorch 2.1.2 with CUDA 12.1..."
"${PIP}" install torch==2.1.2 torchvision==0.16.2 torchaudio==2.1.2 \
    --index-url https://download.pytorch.org/whl/cu121

echo "[$(date)] Verifying torch CUDA..."
"${ENV}/bin/python" -c "import torch; print('torch', torch.__version__); print('CUDA available:', torch.cuda.is_available()); print('GPU:', torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'none')"

echo "[$(date)] Step 4: Install DGL for torch-2.1 + CUDA 12.1..."
"${PIP}" install dgl -f https://data.dgl.ai/wheels/torch-2.1/cu121/repo.html

echo "[$(date)] Verifying DGL..."
"${ENV}/bin/python" -c "import dgl; print('dgl', dgl.__version__)"

echo "[$(date)] Step 5: Install missing RFdiffusion dependencies..."
"${PIP}" install pyrsistent iopath opt_einsum
"${PIP}" uninstall -y se3-transformer equivariant-attention 2>/dev/null || true
"${PIP}" install "${PROJECT}/tools/RFdiffusion/env/SE3Transformer"
# Install rfdiffusion package itself in editable mode
"${PIP}" install -e "${PROJECT}/tools/RFdiffusion" --no-deps

echo "[$(date)] Step 6: Verify full RFdiffusion import..."
"${ENV}/bin/python" -c "
import sys
sys.path.insert(0, '${PROJECT}/tools/RFdiffusion')
from rfdiffusion.util import writepdb_multi, writepdb
from rfdiffusion.inference import utils as iu
print('RFdiffusion imports OK')
"

echo ""
echo "[$(date)] enz_rfdiffusion env fixed for CUDA 12 / H200."
echo "  numpy: $("${ENV}/bin/python" -c 'import numpy; print(numpy.__version__)')"
echo "  torch: $("${ENV}/bin/python" -c 'import torch; print(torch.__version__)')"
echo "  dgl:   $("${ENV}/bin/python" -c 'import dgl; print(dgl.__version__)')"
