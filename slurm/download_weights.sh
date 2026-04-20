#!/usr/bin/env bash
#SBATCH --job-name=enz_weights
#SBATCH --output=/hpc/group/naderilab/darian/Enz/slurm/logs/weights_%j.out
#SBATCH --error=/hpc/group/naderilab/darian/Enz/slurm/logs/weights_%j.err
#SBATCH --partition=common
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=4:00:00
# Downloads all model weights and installs localcolabfold.
# Envs and tool clones are already done — this is the only remaining step.

set -euo pipefail

PROJECT=/hpc/group/naderilab/darian/Enz
TOOLS=${PROJECT}/tools
WEIGHTS=${PROJECT}/weights

echo "Started: $(date)"

# ---------------------------------------------------------------------------
# RFdiffusion weights
# ---------------------------------------------------------------------------
mkdir -p "${WEIGHTS}/rfdiffusion"

dl() {
    local url="$1" dest="$2"
    if [ ! -s "${dest}" ]; then   # -s = exists AND non-empty
        echo "Downloading $(basename ${dest})..."
        wget --retry-connrefused --tries=5 --waitretry=10 \
             --show-progress -q "${url}" -O "${dest}"
        echo "  Done: $(du -sh ${dest} | cut -f1)"
    else
        echo "  $(basename ${dest}) already present ($(du -sh ${dest} | cut -f1))"
    fi
}

dl "http://files.ipd.uw.edu/pub/RFdiffusion/6f5902ac237024bdd0c176cb93063dc4/Base_ckpt.pt" \
   "${WEIGHTS}/rfdiffusion/Base_ckpt.pt"

dl "http://files.ipd.uw.edu/pub/RFdiffusion/f572d396fae9206628714fb2ce00f72e/ActiveSite_ckpt.pt" \
   "${WEIGHTS}/rfdiffusion/ActiveSite_ckpt.pt"

# ---------------------------------------------------------------------------
# localcolabfold + AlphaFold2 weights
# ---------------------------------------------------------------------------
if [ ! -d "${TOOLS}/localcolabfold/colabfold-conda" ]; then
    echo "Installing localcolabfold..."
    cd "${TOOLS}"
    wget -q "https://raw.githubusercontent.com/YoshitakaMo/localcolabfold/main/install_colabfold_linux.sh"
    bash install_colabfold_linux.sh
    rm -f install_colabfold_linux.sh
else
    echo "localcolabfold already installed."
fi

echo "Downloading AlphaFold2 weights..."
mkdir -p "${WEIGHTS}/alphafold"
CF_PYTHON="${TOOLS}/localcolabfold/colabfold-conda/bin/python"
"${CF_PYTHON}" -m colabfold.download "${WEIGHTS}/alphafold"

echo ""
echo "All weights complete: $(date)"
ls -lh "${WEIGHTS}/rfdiffusion/"
