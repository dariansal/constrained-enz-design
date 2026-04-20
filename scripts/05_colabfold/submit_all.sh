#!/usr/bin/env bash
# =============================================================================
# submit_all.sh (ColabFold)
# Submits one SLURM job per experiment for structure prediction.
# =============================================================================
set -euo pipefail

PROJECT=/hpc/group/naderilab/darian/Enz
TEMPLATE=${PROJECT}/scripts/05_colabfold/run_colabfold.sh

ENZYMES=("1ppf" "1ca2")
REGIMES=("motif_only" "shell5" "shell8")

DEPENDS=""
if [[ "${1:-}" == "--after-jobs" && -n "${2:-}" ]]; then
    DEPENDS="--dependency=afterok:${2}"
fi

echo "Submitting ColabFold jobs..."
JOB_IDS=()

for ENZ in "${ENZYMES[@]}"; do
    for REGIME in "${REGIMES[@]}"; do
        EXP="${ENZ}_${REGIME}"
        MPNN_FASTA="${PROJECT}/results/proteinmpnn/${EXP}/${EXP}_all_seqs.fasta"

        SCRIPT_OUT="${PROJECT}/slurm/cf_${EXP}.sh"
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
echo "All ColabFold jobs submitted: ${JOB_IDS[*]}"
echo "After completion, run:"
echo "  python scripts/06_analysis/compute_metrics.py"
