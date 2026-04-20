#!/usr/bin/env bash
# =============================================================================
# download_weights.sh
# Downloads model weights for RFdiffusion, ProteinMPNN, and AlphaFold2.
# Can be run on login node (no GPU needed). Requires internet access.
# Total download: ~7 GB
# =============================================================================
set -euo pipefail

WEIGHTS=/hpc/group/naderilab/darian/Enz/weights

echo "Downloading model weights to ${WEIGHTS}/"
echo "Expected total: ~7 GB"

# ---------------------------------------------------------------------------
# RFdiffusion weights
# Source: https://files.ipd.uw.edu/pub/RFdiffusion/
# ---------------------------------------------------------------------------
echo ""
echo "[1/3] Downloading RFdiffusion weights (~1.1 GB)..."

mkdir -p "${WEIGHTS}/rfdiffusion"

# Main model (used for scaffolding)
if [ ! -f "${WEIGHTS}/rfdiffusion/Base_ckpt.pt" ]; then
    wget -q --show-progress \
        "http://files.ipd.uw.edu/pub/RFdiffusion/6f5902ac237024bdd0c176cb93063dc6/Base_ckpt.pt" \
        -O "${WEIGHTS}/rfdiffusion/Base_ckpt.pt"
fi

# ActiveSite model (specialized for active-site scaffolding — ideal for this project)
if [ ! -f "${WEIGHTS}/rfdiffusion/ActiveSite_ckpt.pt" ]; then
    wget -q --show-progress \
        "http://files.ipd.uw.edu/pub/RFdiffusion/f572d396fae9206628714fb2ce00f72e/ActiveSite_ckpt.pt" \
        -O "${WEIGHTS}/rfdiffusion/ActiveSite_ckpt.pt"
fi

# Complex_base model (for multi-chain, useful for metal-binding)
if [ ! -f "${WEIGHTS}/rfdiffusion/Complex_base_ckpt.pt" ]; then
    wget -q --show-progress \
        "http://files.ipd.uw.edu/pub/RFdiffusion/5532d2e1f3a4738decd58b19d633b3c3/Complex_base_ckpt.pt" \
        -O "${WEIGHTS}/rfdiffusion/Complex_base_ckpt.pt"
fi

echo "  RFdiffusion weights done."

# ---------------------------------------------------------------------------
# ProteinMPNN weights
# ---------------------------------------------------------------------------
echo ""
echo "[2/3] ProteinMPNN weights (~200 MB)..."

# ProteinMPNN weights are bundled with the repo clone
MPNN_DIR=/hpc/group/naderilab/darian/Enz/tools/ProteinMPNN
if [ -d "${MPNN_DIR}/vanilla_model_weights" ]; then
    echo "  ProteinMPNN weights found in repo — no separate download needed."
else
    echo "  WARNING: ProteinMPNN not cloned yet. Run install_tools.sh first."
fi

# Optionally download LigandMPNN for the metal-binding case
mkdir -p "${WEIGHTS}/proteinmpnn"
if [ ! -f "${WEIGHTS}/proteinmpnn/ca_model_weights" ]; then
    ln -sf "${MPNN_DIR}/vanilla_model_weights" \
           "${WEIGHTS}/proteinmpnn/vanilla_model_weights" 2>/dev/null || true
fi
echo "  ProteinMPNN weights done."

# ---------------------------------------------------------------------------
# AlphaFold2 / ColabFold weights
# Source: DeepMind release via localcolabfold
# ---------------------------------------------------------------------------
echo ""
echo "[3/3] AlphaFold2 weights (~5 GB via colabfold_download)..."

COLABFOLD_DIR=/hpc/group/naderilab/darian/Enz/tools/localcolabfold
mkdir -p "${WEIGHTS}/alphafold"

if [ -d "${COLABFOLD_DIR}/colabfold-conda" ]; then
    # Use localcolabfold's built-in downloader
    "${COLABFOLD_DIR}/colabfold-conda/bin/python" \
        -m colabfold.download \
        --model-type alphafold2_multimer_v3 \
        "${WEIGHTS}/alphafold/" \
    || echo "  WARNING: colabfold.download failed. Weights may be auto-downloaded on first run."
else
    echo "  localcolabfold not installed yet. Run install_tools.sh first."
    echo "  AlphaFold2 weights will be downloaded automatically on first ColabFold run."
fi

echo ""
echo "========================================================"
echo "Weight downloads complete."
echo "  RFdiffusion:  ${WEIGHTS}/rfdiffusion/"
echo "  ProteinMPNN:  ${WEIGHTS}/proteinmpnn/"
echo "  AlphaFold2:   ${WEIGHTS}/alphafold/"
echo ""
echo "Next: run 01_data/download_pdbs.py"
echo "========================================================"
