#!/usr/bin/env bash
#SBATCH --job-name=enz_setup
#SBATCH --output=/hpc/group/naderilab/darian/Enz/slurm/logs/setup_%j.out
#SBATCH --error=/hpc/group/naderilab/darian/Enz/slurm/logs/setup_%j.err
#SBATCH --partition=common
#SBATCH --cpus-per-task=4
#SBATCH --mem=32G
#SBATCH --time=4:00:00
# =============================================================================
# setup_envs.sh
# Creates all conda environments and downloads model weights.
# Run this FIRST before any experiment jobs.
# Submit with: sbatch slurm/setup_envs.sh
# =============================================================================
set -euo pipefail

PROJECT=/hpc/group/naderilab/darian/Enz
ENV_PREFIX=/hpc/group/naderilab/darian/conda_environments
TOOLS=${PROJECT}/tools
WEIGHTS=${PROJECT}/weights

source /opt/apps/rhel9/Anaconda3-2024.02/etc/profile.d/conda.sh

echo "========================================================"
echo "Environment setup for Enz project"
echo "Started: $(date)"
echo "Node: $(hostname)"
echo "========================================================"

# ---------------------------------------------------------------------------
# enz_proteinmpnn
# ---------------------------------------------------------------------------
if ! conda run -p "${ENV_PREFIX}/enz_proteinmpnn" python -c "import torch" 2>/dev/null; then
    echo "[1/3] Creating enz_proteinmpnn..."
    conda create -y -p "${ENV_PREFIX}/enz_proteinmpnn" python=3.9 -c conda-forge
    conda run -p "${ENV_PREFIX}/enz_proteinmpnn" pip install \
        torch==2.0.1+cu118 --index-url https://download.pytorch.org/whl/cu118
    conda run -p "${ENV_PREFIX}/enz_proteinmpnn" pip install \
        biopython numpy pandas tqdm pyyaml
else
    echo "[1/3] enz_proteinmpnn already exists."
fi

# ---------------------------------------------------------------------------
# enz_11ffusion
# ---------------------------------------------------------------------------
if ! conda run -p "${ENV_PREFIX}/enz_rfdiffusion" python -c "import torch" 2>/dev/null; then
    echo "[2/3] Creating enz_rfdiffusion..."
    conda create -y -p "${ENV_PREFIX}/enz_rfdiffusion" python=3.9 -c conda-forge
    conda run -p "${ENV_PREFIX}/enz_rfdiffusion" pip install \
        torch==2.0.1+cu118 --index-url https://download.pytorch.org/whl/cu118
    conda run -p "${ENV_PREFIX}/enz_rfdiffusion" pip install \
        e3nn==0.3.3 einops==0.3.0 hydra-core==1.3.2 \
        icecream omegaconf opt-einsum pydantic \
        "PyYAML>=5.3.1" scipy tqdm wandb biopython numpy
    # Install DGL (CPU version for env creation, GPU used at inference)
    conda run -p "${ENV_PREFIX}/enz_rfdiffusion" pip install \
        dgl -f https://data.dgl.ai/wheels/cu118/repo.html || \
    conda run -p "${ENV_PREFIX}/enz_rfdiffusion" pip install dgl
else
    echo "[2/3] enz_rfdiffusion already exists."
fi

# ---------------------------------------------------------------------------
# Install RFdiffusion tools
# ---------------------------------------------------------------------------
echo "[Tools] Installing RFdiffusion and ProteinMPNN..."

if [ ! -d "${TOOLS}/RFdiffusion/.git" ]; then
    git clone https://github.com/RosettaCommons/RFdiffusion.git "${TOOLS}/RFdiffusion"
fi
conda run -p "${ENV_PREFIX}/enz_rfdiffusion" pip install \
    "${TOOLS}/RFdiffusion/env/SE3Transformer" --no-deps 2>/dev/null || \
    echo "WARNING: SE3Transformer install issue"

conda run -p "${ENV_PREFIX}/enz_rfdiffusion" pip install \
    -e "${TOOLS}/RFdiffusion" --no-deps 2>/dev/null || true

if [ ! -d "${TOOLS}/ProteinMPNN/.git" ]; then
    git clone https://github.com/dauparas/ProteinMPNN.git "${TOOLS}/ProteinMPNN"
fi

# ---------------------------------------------------------------------------
# Download RFdiffusion weights
# ---------------------------------------------------------------------------
echo "[Weights] Downloading RFdiffusion model weights..."
mkdir -p "${WEIGHTS}/rfdiffusion"

download_if_missing() {
    local url="$1"; local dest="$2"
    if [ ! -f "${dest}" ]; then
        wget -q --show-progress "${url}" -O "${dest}"
    else
        echo "  $(basename ${dest}) already exists."
    fi
}

download_if_missing \
    "http://files.ipd.uw.edu/pub/RFdiffusion/6f5902ac237024bdd0c176cb93063dc6/Base_ckpt.pt" \
    "${WEIGHTS}/rfdiffusion/Base_ckpt.pt"

download_if_missing \
    "http://files.ipd.uw.edu/pub/RFdiffusion/f572d396fae9206628714fb2ce00f72e/ActiveSite_ckpt.pt" \
    "${WEIGHTS}/rfdiffusion/ActiveSite_ckpt.pt"

# ---------------------------------------------------------------------------
# Install ColabFold (localcolabfold) + download AlphaFold2 weights
# ---------------------------------------------------------------------------
echo "[3/3] Installing localcolabfold..."
if [ ! -d "${TOOLS}/localcolabfold/colabfold-conda" ]; then
    cd "${TOOLS}"
    wget -q "https://raw.githubusercontent.com/YoshitakaMo/localcolabfold/main/install_colabfold_linux.sh"
    bash install_colabfold_linux.sh 2>&1 | tail -20
    rm -f install_colabfold_linux.sh
else
    echo "  localcolabfold already installed."
fi

# Download AlphaFold2 weights (~4 GB) so ColabFold jobs don't waste walltime fetching them
echo "[Weights] Downloading AlphaFold2 params..."
mkdir -p "${WEIGHTS}/alphafold"
CF_PYTHON="${TOOLS}/localcolabfold/colabfold-conda/bin/python"
if [ -f "${CF_PYTHON}" ]; then
    "${CF_PYTHON}" -m colabfold.download "${WEIGHTS}/alphafold"
else
    echo "  WARNING: colabfold python not found at ${CF_PYTHON} — weights will download on first run"
fi

echo ""
echo "========================================================"
echo "Setup complete: $(date)"
echo "  enz_proteinmpnn: ${ENV_PREFIX}/enz_proteinmpnn"
echo "  enz_rfdiffusion: ${ENV_PREFIX}/enz_rfdiffusion"
echo "  RFdiffusion:     ${TOOLS}/RFdiffusion"
echo "  ProteinMPNN:     ${TOOLS}/ProteinMPNN"
echo "  localcolabfold:  ${TOOLS}/localcolabfold"
echo "  RFdiff weights:  ${WEIGHTS}/rfdiffusion/"
echo ""
echo "Next steps:"
echo "  1. Verify environments: conda env list"
echo "  2. Submit RFdiffusion: bash ${PROJECT}/scripts/03_rfdiffusion/submit_all.sh"
echo "========================================================"
