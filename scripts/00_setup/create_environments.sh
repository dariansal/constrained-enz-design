#!/usr/bin/env bash
# =============================================================================
# create_environments.sh
# Creates all conda environments for the Enz project.
# Run once on a login node; does NOT require GPU.
# =============================================================================
set -euo pipefail

ENV_PREFIX=/hpc/group/naderilab/darian/conda_environments
PROJECT=/hpc/group/naderilab/darian/Enz

echo "========================================================"
echo "Creating conda environments for Enz project"
echo "Prefix: ${ENV_PREFIX}"
echo "========================================================"

# ---------------------------------------------------------------------------
# 1. enz_analysis — BioPython, numpy, pandas, matplotlib, scipy, seaborn
#    (runs on login node, no GPU needed)
# ---------------------------------------------------------------------------
echo ""
echo "[1/4] Creating enz_analysis..."
conda create -y -p ${ENV_PREFIX}/enz_analysis \
    python=3.10 \
    -c conda-forge -c defaults
conda run -p ${ENV_PREFIX}/enz_analysis pip install \
    biopython==1.83 \
    numpy==1.26.4 \
    pandas==2.2.2 \
    matplotlib==3.8.4 \
    seaborn==0.13.2 \
    scipy==1.13.1 \
    tqdm==4.66.4 \
    requests==2.32.3 \
    pyyaml==6.0.1 \
    mdanalysis==2.7.0 \
    tmtools \
    py3Dmol
echo "  enz_analysis done."

# ---------------------------------------------------------------------------
# 2. enz_rfdiffusion — RFdiffusion + SE3-transformer (CUDA 12.1)
# ---------------------------------------------------------------------------
echo ""
echo "[2/4] Creating enz_rfdiffusion..."
conda create -y -p ${ENV_PREFIX}/enz_rfdiffusion \
    python=3.9 \
    -c conda-forge -c defaults

# PyTorch 2.0 with CUDA 12.1 (compatible with DCC's cuda-12.7)
conda run -p ${ENV_PREFIX}/enz_rfdiffusion pip install \
    torch==2.0.1+cu118 torchvision==0.15.2+cu118 \
    --index-url https://download.pytorch.org/whl/cu118

conda run -p ${ENV_PREFIX}/enz_rfdiffusion pip install \
    dgl -f https://data.dgl.ai/wheels/cu118/repo.html

conda run -p ${ENV_PREFIX}/enz_rfdiffusion pip install \
    assertpy \
    biopython==1.81 \
    e3nn==0.3.3 \
    einops==0.3.0 \
    hydra-core==1.3.2 \
    icecream \
    omegaconf \
    opt-einsum \
    packaging \
    pydantic \
    "PyYAML>=5.3.1" \
    requests \
    scipy \
    tqdm \
    wandb \
    numpy==1.26.4

# SE3 transformer (required by RFdiffusion)
conda run -p ${ENV_PREFIX}/enz_rfdiffusion pip install \
    git+https://github.com/NVIDIA/se3-transformer-public.git \
    || echo "WARNING: SE3 transformer install failed — will retry in install_rfdiffusion.sh"

echo "  enz_rfdiffusion done."

# ---------------------------------------------------------------------------
# 3. enz_proteinmpnn — ProteinMPNN (PyTorch, minimal deps)
# ---------------------------------------------------------------------------
echo ""
echo "[3/4] Creating enz_proteinmpnn..."
conda create -y -p ${ENV_PREFIX}/enz_proteinmpnn \
    python=3.9 \
    -c conda-forge -c defaults

conda run -p ${ENV_PREFIX}/enz_proteinmpnn pip install \
    torch==2.0.1+cu118 \
    --index-url https://download.pytorch.org/whl/cu118

conda run -p ${ENV_PREFIX}/enz_proteinmpnn pip install \
    biopython==1.83 \
    numpy==1.26.4 \
    pandas==2.2.2 \
    tqdm==4.66.4 \
    pyyaml==6.0.1

echo "  enz_proteinmpnn done."

# ---------------------------------------------------------------------------
# 4. enz_colabfold — LocalColabFold / AlphaFold2
# ---------------------------------------------------------------------------
echo ""
echo "[4/4] Creating enz_colabfold..."
conda create -y -p ${ENV_PREFIX}/enz_colabfold \
    python=3.10 \
    -c conda-forge -c defaults

conda run -p ${ENV_PREFIX}/enz_colabfold pip install \
    "colabfold[alphafold]" \
    --find-links https://storage.googleapis.com/jax-releases/jax_cuda_releases.html \
    || true

# Alternative: install via conda-forge (more reliable on HPC)
conda run -p ${ENV_PREFIX}/enz_colabfold pip install \
    colabfold \
    biopython \
    numpy \
    pandas \
    matplotlib \
    tqdm \
    requests

echo "  enz_colabfold done."

echo ""
echo "========================================================"
echo "All environments created. Verify with:"
echo "  conda env list"
echo "Next: run 00_setup/download_weights.sh"
echo "========================================================"
