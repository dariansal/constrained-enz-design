#!/usr/bin/env bash
#SBATCH --job-name=enz_colabfold_install
#SBATCH --output=/hpc/group/naderilab/darian/Enz/slurm/logs/colabfold_install_%j.out
#SBATCH --error=/hpc/group/naderilab/darian/Enz/slurm/logs/colabfold_install_%j.err
#SBATCH --partition=common
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --time=4:00:00
# Miniforge is already installed at tools/localcolabfold/conda.
# This job creates the colabfold-conda env and downloads AF2 weights.

set -euo pipefail

PROJECT=/hpc/group/naderilab/darian/Enz
COLABFOLDDIR=${PROJECT}/tools/localcolabfold
CACHE_DIR=/hpc/group/naderilab/darian/pkg_cache

# Redirect pip and conda caches off the 25G home quota
export PIP_CACHE_DIR="${CACHE_DIR}/pip"
export CONDA_PKGS_DIRS="${CACHE_DIR}/conda_pkgs"
export XDG_CACHE_HOME="${CACHE_DIR}/xdg"
mkdir -p "${PIP_CACHE_DIR}" "${CONDA_PKGS_DIRS}" "${XDG_CACHE_HOME}"

source "${COLABFOLDDIR}/conda/etc/profile.d/conda.sh"
export PATH="${COLABFOLDDIR}/conda/condabin:${PATH}"

echo "[$(date)] Creating colabfold-conda environment..."

# Remove any partial env from the killed attempt
rm -rf "${COLABFOLDDIR}/colabfold-conda"

conda create -p "${COLABFOLDDIR}/colabfold-conda" -c conda-forge -c bioconda \
    git python=3.10 openmm==8.2.0 pdbfixer \
    kalign2=2.04 hhsuite=3.3.0 mmseqs2 -y

conda activate "${COLABFOLDDIR}/colabfold-conda"

echo "[$(date)] Installing colabfold pip packages..."

"${COLABFOLDDIR}/colabfold-conda/bin/pip" install --no-warn-conflicts \
    "colabfold[alphafold-minus-jax] @ git+https://github.com/sokrypton/ColabFold"
"${COLABFOLDDIR}/colabfold-conda/bin/pip" install "colabfold[alphafold]"
"${COLABFOLDDIR}/colabfold-conda/bin/pip" install --upgrade "jax[cuda12]==0.5.3"
"${COLABFOLDDIR}/colabfold-conda/bin/pip" install --upgrade tensorflow
"${COLABFOLDDIR}/colabfold-conda/bin/pip" install silence_tensorflow

echo "[$(date)] Patching colabfold source..."

pushd "${COLABFOLDDIR}/colabfold-conda/lib/python3.10/site-packages/colabfold"
sed -i -e "s#from matplotlib import pyplot as plt#import matplotlib\nmatplotlib.use('Agg')\nimport matplotlib.pyplot as plt#g" plot.py
sed -i -e "s#appdirs.user_cache_dir(__package__ or \"colabfold\")#\"${COLABFOLDDIR}/colabfold\"#g" download.py
sed -i -e "s#from io import StringIO#from io import StringIO\nfrom silence_tensorflow import silence_tensorflow\nsilence_tensorflow()#g" batch.py
rm -rf __pycache__
popd

PARAMS_DIR="${COLABFOLDDIR}/colabfold/params"
echo "[$(date)] Downloading AlphaFold2 weights to ${PARAMS_DIR}..."
mkdir -p "${PARAMS_DIR}"
# download.py argv[1] = model_type (not a path); no args → both multimer_v3 + ptm
"${COLABFOLDDIR}/colabfold-conda/bin/python3" -m colabfold.download

echo ""
echo "[$(date)] Installation complete."
echo "  colabfold_batch: ${COLABFOLDDIR}/colabfold-conda/bin/colabfold_batch"
ls -lh "${PARAMS_DIR}/" | head -10
