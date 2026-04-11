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

N_STEPS="${N_STEPS:-1000000000}"
N_RUNS="${N_RUNS:-48}"
THREADS="${THREADS:-48}"
OUT_ROOT="${OUT_ROOT:-td_cxx_logs_full_1e9_nonzero_theta}"

DEFAULT_ENVS_CSV="toyexample,E1,E2,E3,E4,E5,E6,E7,E8,E9,E10"
ENVS_CSV="${ENVS_CSV:-$DEFAULT_ENVS_CSV}"
IFS=',' read -r -a ENVS <<< "$ENVS_CSV"

mkdir -p "$OUT_ROOT"

START_TS="$(date +%Y%m%d_%H%M%S)"
MASTER_LOG="$OUT_ROOT/full_run_nonzero_theta_${START_TS}.log"

echo "[info] start_ts=$START_TS" | tee -a "$MASTER_LOG"
echo "[info] n_steps=$N_STEPS n_runs=$N_RUNS threads=$THREADS" | tee -a "$MASTER_LOG"
echo "[info] out_root=$OUT_ROOT" | tee -a "$MASTER_LOG"
echo "[info] base_values=$BASE_VALUES" | tee -a "$MASTER_LOG"
echo "[info] envs=$ENVS_CSV" | tee -a "$MASTER_LOG"

for env in "${ENVS[@]}"; do
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
    --schedules theory \
    --projections none \
    --threads "$THREADS" \
    --outdir "$OUT_ROOT" \
    --skip_plots 2>&1 | tee -a "$MASTER_LOG"

  run_dir="$(ls -dt "$OUT_ROOT/${env}_"* 2>/dev/null | head -n1 || true)"
  if [[ -z "$run_dir" ]]; then
    echo "[error] failed to locate run directory for $env under $OUT_ROOT" | tee -a "$MASTER_LOG"
    exit 1
  fi
  manifest_path="$run_dir/manifest.tsv"
  if [[ ! -f "$manifest_path" ]]; then
    echo "[error] manifest missing: $manifest_path" | tee -a "$MASTER_LOG"
    exit 1
  fi

  python3 - "$manifest_path" "$env" <<'PY' | tee -a "$MASTER_LOG"
import csv
import math
import sys

manifest_path = sys.argv[1]
env = sys.argv[2]
with open(manifest_path, "r", newline="", encoding="utf-8") as f:
    rows = list(csv.DictReader(f, delimiter="\t"))

if not rows:
    print(f"[error] empty manifest for {env}: {manifest_path}")
    sys.exit(1)

vals = []
for r in rows:
    try:
        vals.append(float(r["theta_star_norm"]))
    except Exception:
        print(f"[error] invalid theta_star_norm in {manifest_path}")
        sys.exit(1)

ok = all(math.isfinite(v) and v > 0.0 for v in vals)
if not ok:
    vmin = min(vals) if vals else float("nan")
    vmax = max(vals) if vals else float("nan")
    print(f"[error] theta_star_norm non-positive or non-finite for {env}: min={vmin} max={vmax} manifest={manifest_path}")
    sys.exit(1)

print(f"[check] {env} theta_star_norm > 0 confirmed: min={min(vals):.12g}, max={max(vals):.12g}")
PY
done

echo "[info] all environments finished with theta_star_norm > 0 checks passed" | tee -a "$MASTER_LOG"
