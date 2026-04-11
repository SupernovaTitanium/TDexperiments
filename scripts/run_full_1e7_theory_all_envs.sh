#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if [[ ! -x ./cpp/tdx ]]; then
  echo "[info] building cpp/tdx"
  make -C cpp
fi

# Half-decade logarithmic sweep from 1e-5 to 1e3 (override via env BASE_VALUES).
DEFAULT_BASE_VALUES="1e-5,3.16227766017e-5,1e-4,3.16227766017e-4,1e-3,3.16227766017e-3,1e-2,3.16227766017e-2,1e-1,3.16227766017e-1,1,3.16227766017,1e1,3.16227766017e1,1e2,3.16227766017e2,1e3"
BASE_VALUES="${BASE_VALUES:-$DEFAULT_BASE_VALUES}"

N_STEPS="${N_STEPS:-10000000}"
N_RUNS="${N_RUNS:-48}"
THREADS="${THREADS:-48}"
OUT_ROOT="${OUT_ROOT:-td_cxx_logs_full_1e7}"

DEFAULT_ENVS_CSV="toyexample,E1,E2,E3,E4,E5,E6,E7,E8,E9,E10"
ENVS_CSV="${ENVS_CSV:-$DEFAULT_ENVS_CSV}"
IFS=',' read -r -a ENVS <<< "$ENVS_CSV"

mkdir -p "$OUT_ROOT"

START_TS="$(date +%Y%m%d_%H%M%S)"
MASTER_LOG="$OUT_ROOT/full_run_${START_TS}.log"

echo "[info] start_ts=$START_TS" | tee -a "$MASTER_LOG"
echo "[info] n_steps=$N_STEPS n_runs=$N_RUNS threads=$THREADS" | tee -a "$MASTER_LOG"
echo "[info] out_root=$OUT_ROOT" | tee -a "$MASTER_LOG"
echo "[info] envs=$ENVS_CSV" | tee -a "$MASTER_LOG"

for env in "${ENVS[@]}"; do
  echo "[info] ===== env=$env =====" | tee -a "$MASTER_LOG"

  EXTRA_ARGS=()
  if [[ "$env" == "toyexample" ]]; then
    EXTRA_ARGS+=(--set scale_factor=1.0)
  fi

  # Each env writes to OUT_ROOT/<env>_<timestamp>.
  ./cpp/tdx sweep \
    --env "$env" \
    "${EXTRA_ARGS[@]}" \
    --n_steps "$N_STEPS" \
    --n_runs "$N_RUNS" \
    --base_values "$BASE_VALUES" \
    --schedules theory \
    --projections none \
    --threads "$THREADS" \
    --outdir "$OUT_ROOT" \
    --skip_plots 2>&1 | tee -a "$MASTER_LOG"
done

echo "[info] all environments finished" | tee -a "$MASTER_LOG"
