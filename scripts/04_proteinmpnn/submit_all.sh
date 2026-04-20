#!/usr/bin/env bash
# =============================================================================
# submit_all.sh (ProteinMPNN)
# Submits one SLURM job per experiment, after RFdiffusion has completed.
#
# Pass --wait to block until jobs finish.
# Usage: bash scripts/04_proteinmpnn/submit_all.sh [--after-jobs JID1,JID2,...]
# =============================================================================
set -euo pipefail

PROJECT=/hpc/group/naderilab/darian/Enz
TEMPLATE=${PROJECT}/scripts/04_proteinmpnn/run_proteinmpnn.sh

ENZYMES=("1ppf" "1ca2")
REGIMES=("motif_only" "shell5" "shell8")

# Optional: wait for RFdiffusion jobs first
DEPENDS=""
if [[ "${1:-}" == "--after-jobs" && -n "${2:-}" ]]; then
    DEPENDS="--dependency=afterok:${2}"
fi

echo "Submitting ProteinMPNN jobs..."
JOB_IDS=()

for ENZ in "${ENZYMES[@]}"; do
    for REGIME in "${REGIMES[@]}"; do
        EXP="${ENZ}_${REGIME}"
        RF_OUT="${PROJECT}/results/rfdiffusion/${EXP}"

        SCRIPT_OUT="${PROJECT}/slurm/mpnn_${EXP}.sh"
        sed -e "s/ENZ_REGIME/${EXP}/g" \
            -e "s/^ENZ=\"ENZ\"/ENZ=\"${ENZ}\"/" \
            -e "s/^REGIME=\"REGIME\"/REGIME=\"${REGIME}\"/" \
            "${TEMPLATE}" > "${SCRIPT_OUT}"
        chmod +x "${SCRIPT_OUT}"

        SBATCH_ARGS=()
        [[ -n "${DEPENDS}" ]] && SBATCH_ARGS+=("${DEPENDS}")
        JOB_ID=$(sbatch --parsable "${SBATCH_ARGS[@]+"${SBATCH_ARGS[@]}"}" "${SCRIPT_OUT}")
        JOB_IDS+=("${JOB_ID}")
        echo "  Submitted ${EXP} → Job ${JOB_ID}"
    done
done

echo ""
echo "All ProteinMPNN jobs submitted: ${JOB_IDS[*]}"
echo "After completion, run:"
echo "  bash scripts/05_colabfold/submit_all.sh"
