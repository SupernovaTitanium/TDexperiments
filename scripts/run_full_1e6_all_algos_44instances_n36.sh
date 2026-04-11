#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

if [[ ! -x ./cpp/tdx ]]; then
  echo "[info] building cpp/tdx"
  make -C cpp
fi

N_STEPS="${N_STEPS:-1000000}"
N_RUNS="${N_RUNS:-36}"
THREADS="${THREADS:-36}"
T0="${T0:-0}"
OUT_ROOT="${OUT_ROOT:-td_cxx_logs_full_1e6_n36_44instances}"

# User-requested c grid.
BASE_VALUES="${BASE_VALUES:-10000,1000,100,10,1,0.1,0.01}"
SCHEDULES="${SCHEDULES:-theory,theory_log2,inv_t,inv_sqrt_t,inv_t_2_3,inv_omega_t,constant_omega,constant}"
PROJECTIONS="${PROJECTIONS:-none,oracle,upper}"

ENVS=(toyexample E1 E2 E3 E4 E5 E6 E7 E8 E9 E10)
CASES_PER_ENV="${CASES_PER_ENV:-4}"

mkdir -p "$OUT_ROOT"

START_TS_HUMAN="$(date +%Y%m%d_%H%M%S)"
START_TS_EPOCH="$(date +%s)"
MASTER_LOG="$OUT_ROOT/full_run_1e6_n36_44instances_${START_TS_HUMAN}.log"

format_seconds() {
  local secs="$1"
  if (( secs < 0 )); then secs=0; fi
  local h=$((secs / 3600))
  local m=$(((secs % 3600) / 60))
  local s=$((secs % 60))
  printf "%02dh:%02dm:%02ds" "$h" "$m" "$s"
}

count_csv_items() {
  python3 - "$1" <<'PY'
import sys
items = [x.strip() for x in sys.argv[1].split(",") if x.strip()]
print(len(items))
PY
}

manifest_rows_and_cases() {
  python3 - "$1" <<'PY'
import csv
import sys
path = sys.argv[1]
with open(path, "r", newline="", encoding="utf-8") as f:
    rows = list(csv.DictReader(f, delimiter="\t"))
case_ids = sorted({r.get("case_id", "") for r in rows if r.get("case_id", "")})
print(f"{len(rows)}\t{len(case_ids)}")
PY
}

N_C="$(count_csv_items "$BASE_VALUES")"
N_S="$(count_csv_items "$SCHEDULES")"
N_P="$(count_csv_items "$PROJECTIONS")"
ROWS_PER_CASE=$((N_C * N_S * N_P))
ROWS_PER_ENV=$((ROWS_PER_CASE * CASES_PER_ENV))
EXPECTED_TOTAL_ROWS=$((ROWS_PER_ENV * ${#ENVS[@]}))
HALF_ROWS=$(((EXPECTED_TOTAL_ROWS + 1) / 2))

echo "[info] start_ts=$START_TS_HUMAN" | tee -a "$MASTER_LOG"
echo "[info] n_steps=$N_STEPS n_runs=$N_RUNS threads=$THREADS t0=$T0" | tee -a "$MASTER_LOG"
echo "[info] out_root=$OUT_ROOT" | tee -a "$MASTER_LOG"
echo "[info] envs=${ENVS[*]}" | tee -a "$MASTER_LOG"
echo "[info] expected_cases_per_env=$CASES_PER_ENV total_expected_cases=$((CASES_PER_ENV * ${#ENVS[@]}))" | tee -a "$MASTER_LOG"
echo "[info] base_values=$BASE_VALUES (count=$N_C)" | tee -a "$MASTER_LOG"
echo "[info] schedules=$SCHEDULES (count=$N_S)" | tee -a "$MASTER_LOG"
echo "[info] projections=$PROJECTIONS (count=$N_P)" | tee -a "$MASTER_LOG"
echo "[info] rows_per_case=$ROWS_PER_CASE rows_per_env=$ROWS_PER_ENV expected_total_rows=$EXPECTED_TOTAL_ROWS" | tee -a "$MASTER_LOG"

TOTAL_DONE_ROWS=0
HALF_REPORTED=0

for env in "${ENVS[@]}"; do
  ENV_START_EPOCH="$(date +%s)"
  echo "[info] ===== env=$env =====" | tee -a "$MASTER_LOG"

  EXTRA_ARGS=()
  case "$env" in
    toyexample)
      EXTRA_ARGS+=(--set scale_factor=1.0 --set seed=114514)
      ;;
    E1|E2)
      EXTRA_ARGS+=(--set reward_mode=driven --set rho=1.0)
      ;;
    E3)
      EXTRA_ARGS+=(--set reward_mode=signed --set rho=1.0)
      ;;
    E4)
      EXTRA_ARGS+=(--set reward_mode=single-site --set rho=1.0)
      ;;
    E5)
      EXTRA_ARGS+=(--set reward_mode=launch --set rho=1.0)
      ;;
    E6)
      EXTRA_ARGS+=(--set reward_mode=single-harmonic --set rho=1.0)
      ;;
    E7)
      EXTRA_ARGS+=(--set reward_mode=uniform --set rho=1.0)
      ;;
    E8)
      EXTRA_ARGS+=(--set reward_mode=signed-cycle --set rho=1.0)
      ;;
    E9)
      EXTRA_ARGS+=(--set reward_mode=linear --set rho=1.0)
      ;;
    E10)
      EXTRA_ARGS+=(--set reward_mode=cluster-opposite --set rho=1.0)
      ;;
    *)
      echo "[error] unexpected env id: $env" | tee -a "$MASTER_LOG"
      exit 1
      ;;
  esac

  ./cpp/tdx sweep \
    --env "$env" \
    "${EXTRA_ARGS[@]}" \
    --n_steps "$N_STEPS" \
    --n_runs "$N_RUNS" \
    --base_values "$BASE_VALUES" \
    --schedules "$SCHEDULES" \
    --projections "$PROJECTIONS" \
    --t0 "$T0" \
    --threads "$THREADS" \
    --outdir "$OUT_ROOT" \
    --skip_plots 2>&1 | tee -a "$MASTER_LOG"

  RUN_DIR="$(ls -dt "$OUT_ROOT/${env}_"* 2>/dev/null | head -n1 || true)"
  if [[ -z "$RUN_DIR" ]]; then
    echo "[error] failed to locate run directory for env=$env under $OUT_ROOT" | tee -a "$MASTER_LOG"
    exit 1
  fi
  MANIFEST_PATH="$RUN_DIR/manifest.tsv"
  if [[ ! -f "$MANIFEST_PATH" ]]; then
    echo "[error] missing manifest: $MANIFEST_PATH" | tee -a "$MASTER_LOG"
    exit 1
  fi

  STATS="$(manifest_rows_and_cases "$MANIFEST_PATH")"
  ENV_ROWS="$(printf "%s" "$STATS" | awk '{print $1}')"
  ENV_CASES="$(printf "%s" "$STATS" | awk '{print $2}')"

  if [[ "$ENV_CASES" -ne "$CASES_PER_ENV" ]]; then
    echo "[error] unexpected case count for env=$env: got=$ENV_CASES expected=$CASES_PER_ENV" | tee -a "$MASTER_LOG"
    exit 1
  fi
  if [[ "$ENV_ROWS" -ne "$ROWS_PER_ENV" ]]; then
    echo "[error] unexpected manifest rows for env=$env: got=$ENV_ROWS expected=$ROWS_PER_ENV" | tee -a "$MASTER_LOG"
    exit 1
  fi

  TOTAL_DONE_ROWS=$((TOTAL_DONE_ROWS + ENV_ROWS))
  NOW_EPOCH="$(date +%s)"
  ENV_ELAPSED=$((NOW_EPOCH - ENV_START_EPOCH))
  TOTAL_ELAPSED=$((NOW_EPOCH - START_TS_EPOCH))

  ETA_TOTAL=0
  ETA_REMAIN=0
  if (( TOTAL_DONE_ROWS > 0 )); then
    ETA_TOTAL=$(( TOTAL_ELAPSED * EXPECTED_TOTAL_ROWS / TOTAL_DONE_ROWS ))
    ETA_REMAIN=$(( ETA_TOTAL - TOTAL_ELAPSED ))
    if (( ETA_REMAIN < 0 )); then ETA_REMAIN=0; fi
  fi

  PROGRESS_PCT="$(python3 - "$TOTAL_DONE_ROWS" "$EXPECTED_TOTAL_ROWS" <<'PY'
import sys
done = int(sys.argv[1]); total = int(sys.argv[2])
print(f"{100.0 * done / total:.2f}")
PY
)"

  echo "[progress] env=$env env_elapsed=$(format_seconds "$ENV_ELAPSED") total_done_rows=$TOTAL_DONE_ROWS/$EXPECTED_TOTAL_ROWS (${PROGRESS_PCT}%) total_elapsed=$(format_seconds "$TOTAL_ELAPSED") eta_total=$(format_seconds "$ETA_TOTAL") eta_remaining=$(format_seconds "$ETA_REMAIN")" | tee -a "$MASTER_LOG"

  if (( HALF_REPORTED == 0 && TOTAL_DONE_ROWS >= HALF_ROWS )); then
    HALF_REPORTED=1
    echo "[estimate-half] reached_halfway done_rows=$TOTAL_DONE_ROWS/$EXPECTED_TOTAL_ROWS elapsed=$(format_seconds "$TOTAL_ELAPSED") estimated_total=$(format_seconds "$ETA_TOTAL") estimated_remaining=$(format_seconds "$ETA_REMAIN")" | tee -a "$MASTER_LOG"
  fi
done

END_TS_EPOCH="$(date +%s)"
TOTAL_SECONDS=$((END_TS_EPOCH - START_TS_EPOCH))
echo "[done] all environments finished total_elapsed=$(format_seconds "$TOTAL_SECONDS") total_rows=$TOTAL_DONE_ROWS/$EXPECTED_TOTAL_ROWS" | tee -a "$MASTER_LOG"
echo "[done] master_log=$MASTER_LOG" | tee -a "$MASTER_LOG"
