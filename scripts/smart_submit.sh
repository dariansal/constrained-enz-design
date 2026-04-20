#!/usr/bin/env bash
# =============================================================================
# smart_submit.sh
# Submits a SLURM job with automatic GPU tier escalation.
#
# Tries GPUs in order until one has a < 10-minute queue wait:
#   1. h200_1g.18gb  (smallest MIG slice, fastest to get)
#   2. h200_3g.71gb  (medium slice)
#   3. h200:1        (full H200, 141 GB)
#
# Usage:
#   bash scripts/smart_submit.sh <slurm_script.sh> [extra_sbatch_args...]
#
# Returns the final job ID on stdout so callers can chain dependencies.
# =============================================================================
set -euo pipefail

SCRIPT="${1:?Usage: smart_submit.sh <slurm_script>}"
shift
EXTRA_ARGS=("$@")

WAIT_MINUTES=10
GPU_TIERS=(
    "h200_1g.18gb:1"
    "h200_3g.71gb:1"
    "h200:1"
)

# ---------------------------------------------------------------------------
# submit_with_gres <gres_string> <script>
# Substitutes the gres line in the script and submits. Returns job ID.
# ---------------------------------------------------------------------------
submit_with_gres() {
    local gres="$1"
    local base_script="$2"
    local tmp_script
    tmp_script=$(mktemp /tmp/enz_job_XXXXXX.sh)
    sed "s|--gres=gpu:h200[^[:space:]]*|--gres=gpu:${gres}|g" \
        "${base_script}" > "${tmp_script}"
    local job_id
    job_id=$(sbatch --parsable "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}" "${tmp_script}")
    rm -f "${tmp_script}"
    echo "${job_id}"
}

# ---------------------------------------------------------------------------
# Main escalation loop — actually wait 10 minutes, then check real state
# ---------------------------------------------------------------------------
JOB_ID=""

for i in "${!GPU_TIERS[@]}"; do
    gres="${GPU_TIERS[$i]}"
    echo "  Trying --gres=gpu:${gres} ..." >&2

    JOB_ID=$(submit_with_gres "${gres}" "${SCRIPT}")
    echo "  Submitted job ${JOB_ID} (gres=${gres})" >&2

    # Last tier: keep unconditionally
    if (( i == ${#GPU_TIERS[@]} - 1 )); then
        echo "  Final tier — keeping job ${JOB_ID}." >&2
        break
    fi

    # Wait the full 10 minutes then check actual state
    echo "  Waiting ${WAIT_MINUTES} min to see if job starts..." >&2
    sleep $(( WAIT_MINUTES * 60 ))

    STATE=$(squeue -j "${JOB_ID}" --format="%T" --noheader 2>/dev/null | tr -d ' ')

    if [[ "${STATE}" != "PENDING" ]]; then
        echo "  Job ${JOB_ID} is ${STATE:-done} — keeping it." >&2
        break
    fi

    echo "  Still PENDING after ${WAIT_MINUTES} min — cancelling and escalating to ${GPU_TIERS[$((i+1))]}..." >&2
    scancel "${JOB_ID}" 2>/dev/null || true
done

echo "${JOB_ID}"
