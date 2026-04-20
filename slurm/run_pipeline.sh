#!/usr/bin/env bash
#SBATCH --job-name=enz_pipeline
#SBATCH --output=/hpc/group/naderilab/darian/Enz/slurm/logs/pipeline_%j.out
#SBATCH --error=/hpc/group/naderilab/darian/Enz/slurm/logs/pipeline_%j.err
#SBATCH --partition=common
#SBATCH --cpus-per-task=1
#SBATCH --mem=4G
#SBATCH --time=8:00:00
# Thin orchestrator — submits all experiment jobs with dependency chaining.
# smart_submit.sh can wait up to 10 min × 6 jobs per stage, so 8h is safe.

set -euo pipefail

PROJECT=/hpc/group/naderilab/darian/Enz
ANA_ENV=/hpc/group/naderilab/darian/conda_environments/enz_analysis

source /opt/apps/rhel9/Anaconda3-2024.02/etc/profile.d/conda.sh

echo "[$(date)] Weights job done. Launching experiment pipeline..."

# ---------------------------------------------------------------------------
# Helper: run a submit_all.sh and return its job IDs as a colon-separated list
# ---------------------------------------------------------------------------
collect_job_ids() {
    # submit_all.sh prints "All jobs submitted: JID1 JID2 ..."  on the last line
    local output
    output=$(bash "$@" 2>/dev/null)
    echo "${output}"  # so caller can see it
    # extract the space-separated IDs from the last line, convert to colon-separated
    echo "${output}" | grep "^All jobs submitted:" | grep -oP '\d+' | paste -sd ':'
}

# ---------------------------------------------------------------------------
# Stage 1: RFdiffusion
# ---------------------------------------------------------------------------
echo ""
echo "=== RFdiffusion ==="
RF_OUT=$(bash "${PROJECT}/scripts/03_rfdiffusion/submit_all.sh" 2>/dev/null)
echo "${RF_OUT}"
RF_CSV=$(echo "${RF_OUT}" | grep "^All jobs submitted:" | grep -oP '\d+' | paste -sd ':')
echo "RF job IDs: ${RF_CSV}"

# ---------------------------------------------------------------------------
# Stage 2: ProteinMPNN — depends on all RFdiffusion jobs
# ---------------------------------------------------------------------------
echo ""
echo "=== ProteinMPNN ==="
MPNN_OUT=$(bash "${PROJECT}/scripts/04_proteinmpnn/submit_all.sh" \
               --after-jobs "${RF_CSV}" 2>/dev/null)
echo "${MPNN_OUT}"
MPNN_CSV=$(echo "${MPNN_OUT}" | grep "^All ProteinMPNN" | grep -oP '\d+' | paste -sd ':')
echo "MPNN job IDs: ${MPNN_CSV}"

# ---------------------------------------------------------------------------
# Stage 3: ColabFold — depends on all ProteinMPNN jobs
# ---------------------------------------------------------------------------
echo ""
echo "=== ColabFold ==="
CF_OUT=$(bash "${PROJECT}/scripts/05_colabfold/submit_all.sh" \
              --after-jobs "${MPNN_CSV}" 2>/dev/null)
echo "${CF_OUT}"
CF_CSV=$(echo "${CF_OUT}" | grep "^All ColabFold" | grep -oP '\d+' | paste -sd ':')
echo "ColabFold job IDs: ${CF_CSV}"

# ---------------------------------------------------------------------------
# Stage 4: Analysis — submit as a dependent job after ColabFold
# ---------------------------------------------------------------------------
echo ""
echo "=== Analysis ==="
ANALYSIS_SCRIPT=$(mktemp /tmp/enz_analysis_XXXXXX.sh)
cat > "${ANALYSIS_SCRIPT}" << HEREDOC
#!/usr/bin/env bash
#SBATCH --job-name=enz_analysis
#SBATCH --output=${PROJECT}/slurm/logs/analysis_%j.out
#SBATCH --partition=common
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#SBATCH --time=1:00:00
source /opt/apps/rhel9/Anaconda3-2024.02/etc/profile.d/conda.sh
conda run -p ${ANA_ENV} python ${PROJECT}/scripts/06_analysis/compute_metrics.py
conda run -p ${ANA_ENV} python ${PROJECT}/scripts/06_analysis/plot_results.py
echo "Analysis complete. Figures: ${PROJECT}/results/analysis/figures/"
HEREDOC

ANALYSIS_JOB=$(sbatch --parsable \
    --dependency=afterok:"${CF_CSV}" \
    "${ANALYSIS_SCRIPT}")
rm -f "${ANALYSIS_SCRIPT}"
echo "Analysis job: ${ANALYSIS_JOB}"

echo ""
echo "[$(date)] Full pipeline submitted."
echo "  RFdiffusion:  ${RF_CSV}"
echo "  ProteinMPNN:  ${MPNN_CSV}"
echo "  ColabFold:    ${CF_CSV}"
echo "  Analysis:     ${ANALYSIS_JOB}"
echo ""
echo "Monitor: squeue -u \$USER"
