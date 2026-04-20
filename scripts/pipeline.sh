#!/usr/bin/env bash
# =============================================================================
# pipeline.sh
# Full experiment pipeline: setup → data → motifs → RFdiffusion → ProteinMPNN
#                           → ColabFold → analysis
#
# Run stages individually (recommended) or all at once.
# All SLURM jobs are submitted with proper dependency chaining.
#
# Usage:
#   bash scripts/pipeline.sh --stage setup      # create envs + download weights
#   bash scripts/pipeline.sh --stage data        # download PDBs + extract motifs
#   bash scripts/pipeline.sh --stage rfdiffusion # submit backbone generation jobs
#   bash scripts/pipeline.sh --stage proteinmpnn # submit sequence design jobs
#   bash scripts/pipeline.sh --stage colabfold   # submit structure prediction jobs
#   bash scripts/pipeline.sh --stage analysis    # compute metrics and plot
#   bash scripts/pipeline.sh --stage all         # run everything (careful!)
# =============================================================================
set -euo pipefail

PROJECT=/hpc/group/naderilab/darian/Enz
ENV_PREFIX=/hpc/group/naderilab/darian/conda_environments
ANA_ENV=${ENV_PREFIX}/enz_analysis

source /opt/apps/rhel9/Anaconda3-2024.02/etc/profile.d/conda.sh

STAGE="${1:-}"
if [[ -z "${STAGE}" ]]; then
    echo "Usage: bash $0 --stage <stage>"
    echo "Stages: setup | data | rfdiffusion | proteinmpnn | colabfold | analysis | all"
    exit 1
fi
STAGE="${2:-${STAGE#--stage=}}"   # handle both --stage=X and --stage X

case "${STAGE}" in

# ---------------------------------------------------------------------------
setup)
    echo "[1/6] Setup: creating environments and downloading weights"
    bash "${PROJECT}/scripts/00_setup/create_environments.sh"
    bash "${PROJECT}/scripts/00_setup/install_tools.sh"
    bash "${PROJECT}/scripts/00_setup/download_weights.sh"
    echo "Setup complete."
    ;;

# ---------------------------------------------------------------------------
data)
    echo "[2/6] Data: downloading PDBs and extracting motifs"
    conda run -p "${ANA_ENV}" python "${PROJECT}/scripts/01_data/download_pdbs.py"
    conda run -p "${ANA_ENV}" python "${PROJECT}/scripts/02_motifs/extract_motifs.py"
    echo "Data stage complete."
    ;;

# ---------------------------------------------------------------------------
rfdiffusion)
    echo "[3/6] RFdiffusion: submitting backbone generation jobs"
    bash "${PROJECT}/scripts/03_rfdiffusion/submit_all.sh"
    echo "RFdiffusion jobs submitted. Monitor: squeue -u \$USER"
    echo "After completion, run: bash pipeline.sh --stage proteinmpnn"
    ;;

# ---------------------------------------------------------------------------
proteinmpnn)
    echo "[4/6] ProteinMPNN: submitting sequence design jobs"
    bash "${PROJECT}/scripts/04_proteinmpnn/submit_all.sh"
    echo "ProteinMPNN jobs submitted."
    ;;

# ---------------------------------------------------------------------------
colabfold)
    echo "[5/6] ColabFold: submitting structure prediction jobs"
    bash "${PROJECT}/scripts/05_colabfold/submit_all.sh"
    echo "ColabFold jobs submitted."
    ;;

# ---------------------------------------------------------------------------
analysis)
    echo "[6/6] Analysis: computing metrics and generating figures"
    conda run -p "${ANA_ENV}" python "${PROJECT}/scripts/06_analysis/compute_metrics.py"
    conda run -p "${ANA_ENV}" python "${PROJECT}/scripts/06_analysis/plot_results.py"
    echo "Analysis complete. See: results/analysis/figures/"
    ;;

# ---------------------------------------------------------------------------
all)
    echo "Running full pipeline with SLURM job chaining..."

    # Stage 1: data (no GPU needed)
    conda run -p "${ANA_ENV}" python "${PROJECT}/scripts/01_data/download_pdbs.py"
    conda run -p "${ANA_ENV}" python "${PROJECT}/scripts/02_motifs/extract_motifs.py"

    # Stage 2: RFdiffusion — submit all, collect job IDs
    echo "Submitting RFdiffusion..."
    RF_IDS=$(bash "${PROJECT}/scripts/03_rfdiffusion/submit_all.sh" 2>&1 | \
             grep "Submitted" | awk '{print $NF}' | paste -sd ',')
    echo "  RFdiffusion jobs: ${RF_IDS}"

    # Stage 3: ProteinMPNN — depends on RFdiffusion
    echo "Submitting ProteinMPNN (after RFdiffusion)..."
    MPNN_IDS=$(bash "${PROJECT}/scripts/04_proteinmpnn/submit_all.sh" \
               --after-jobs "${RF_IDS}" 2>&1 | \
               grep "Submitted" | awk '{print $NF}' | paste -sd ',')

    # Stage 4: ColabFold — depends on ProteinMPNN
    echo "Submitting ColabFold (after ProteinMPNN)..."
    bash "${PROJECT}/scripts/05_colabfold/submit_all.sh" \
         --after-jobs "${MPNN_IDS}"

    echo ""
    echo "Full pipeline submitted. Check progress: squeue -u \$USER"
    echo "When all jobs complete, run: bash pipeline.sh --stage analysis"
    ;;

*)
    echo "Unknown stage: ${STAGE}"
    echo "Valid stages: setup | data | rfdiffusion | proteinmpnn | colabfold | analysis | all"
    exit 1
    ;;
esac
