#!/usr/bin/env bash
# =============================================================================
# install_tools.sh
# Clones RFdiffusion, ProteinMPNN, and ColabFold into the tools/ directory.
# Run AFTER create_environments.sh on a login node.
# =============================================================================
set -euo pipefail

TOOLS=/hpc/group/naderilab/darian/Enz/tools
ENV_PREFIX=/hpc/group/naderilab/darian/conda_environments

echo "Installing protein design tools into ${TOOLS}/"

# ---------------------------------------------------------------------------
# RFdiffusion
# ---------------------------------------------------------------------------
if [ ! -d "${TOOLS}/RFdiffusion/.git" ]; then
    echo "[1/3] Cloning RFdiffusion..."
    git clone https://github.com/RosettaCommons/RFdiffusion.git "${TOOLS}/RFdiffusion"
else
    echo "[1/3] RFdiffusion already cloned — pulling latest..."
    git -C "${TOOLS}/RFdiffusion" pull --ff-only
fi

# Install RFdiffusion as a package into enz_rfdiffusion env
echo "  Installing RFdiffusion package..."
conda run -p ${ENV_PREFIX}/enz_rfdiffusion pip install \
    -e "${TOOLS}/RFdiffusion" \
    --no-deps \
    || true

# Install SE3 transformer if it failed earlier
conda run -p ${ENV_PREFIX}/enz_rfdiffusion pip install \
    "${TOOLS}/RFdiffusion/env/SE3Transformer" \
    || echo "WARNING: SE3Transformer install issue — check manually"

echo "  RFdiffusion installed."

# ---------------------------------------------------------------------------
# ProteinMPNN
# ---------------------------------------------------------------------------
if [ ! -d "${TOOLS}/ProteinMPNN/.git" ]; then
    echo "[2/3] Cloning ProteinMPNN..."
    git clone https://github.com/dauparas/ProteinMPNN.git "${TOOLS}/ProteinMPNN"
else
    echo "[2/3] ProteinMPNN already cloned — pulling latest..."
    git -C "${TOOLS}/ProteinMPNN" pull --ff-only
fi
echo "  ProteinMPNN installed (no build needed — pure Python)."

# ---------------------------------------------------------------------------
# ColabFold (localcolabfold)
# ---------------------------------------------------------------------------
if [ ! -d "${TOOLS}/localcolabfold" ]; then
    echo "[3/3] Installing localcolabfold..."
    # Use the official installer script
    cd "${TOOLS}"
    wget -q "https://raw.githubusercontent.com/YoshitakaMo/localcolabfold/main/install_colabfold_linux.sh"
    bash install_colabfold_linux.sh
    rm -f install_colabfold_linux.sh
    echo "  localcolabfold installed."
else
    echo "[3/3] localcolabfold already installed."
fi

echo ""
echo "All tools installed. Next: run 00_setup/download_weights.sh"
