#!/usr/bin/env bash
# =============================================================================
# submit_all.sh
# Submits one SLURM job per experiment (6 total: 2 enzymes × 3 regimes).
# Prerequisites: extract_motifs.py must have been run successfully.
#
# Usage: bash scripts/03_rfdiffusion/submit_all.sh
# =============================================================================
set -euo pipefail

PROJECT=/hpc/group/naderilab/darian/Enz
SCRIPT_TEMPLATE=${PROJECT}/scripts/03_rfdiffusion/run_rfdiffusion.sh

ENZYMES=("1ppf" "1ca2")
REGIMES=("motif_only" "shell5" "shell8")

echo "Submitting RFdiffusion jobs..."
JOB_IDS=()

for ENZ in "${ENZYMES[@]}"; do
    for REGIME in "${REGIMES[@]}"; do
        EXP="${ENZ}_${REGIME}"
        MOTIF_DIR="${PROJECT}/data/motifs/${EXP}"

        # Verify motif data exists
        if [ ! -f "${MOTIF_DIR}/contig.txt" ]; then
            echo "ERROR: ${MOTIF_DIR}/contig.txt not found. Run extract_motifs.py first."
            exit 1
        fi

        # Create a per-experiment script from the template
        SCRIPT_OUT="${PROJECT}/slurm/rfdiff_${EXP}.sh"
        sed -e "s/ENZ_REGIME/${EXP}/g" \
            -e "s/^ENZ=\"ENZ\"/ENZ=\"${ENZ}\"/" \
            -e "s/^REGIME=\"REGIME\"/REGIME=\"${REGIME}\"/" \
            "${SCRIPT_TEMPLATE}" > "${SCRIPT_OUT}"
        chmod +x "${SCRIPT_OUT}"

        JOB_ID=$(sbatch --parsable "${SCRIPT_OUT}")
        JOB_IDS+=("${JOB_ID}")
        echo "  Submitted ${EXP} → Job ${JOB_ID}"
    done
done

echo ""
echo "All jobs submitted: ${JOB_IDS[*]}"
echo "Monitor: squeue -u \$USER"
echo ""
echo "After completion, run:"
echo "  bash scripts/04_proteinmpnn/submit_all.sh"
