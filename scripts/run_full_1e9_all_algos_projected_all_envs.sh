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
T0="${T0:-0}"
OUT_ROOT="${OUT_ROOT:-td_cxx_logs_full_1e9_all_algos_projected_nonzero_theta}"

SCHEDULES="${SCHEDULES:-theory,theory_log2,inv_t,inv_sqrt_t,inv_t_2_3,inv_omega_t,constant_omega,constant}"
PROJECTIONS="${PROJECTIONS:-none,oracle,upper}"

DEFAULT_ENVS_CSV="toyexample,E1,E2,E3,E4,E5,E6,E7,E8,E9,E10"
ENVS_CSV="${ENVS_CSV:-$DEFAULT_ENVS_CSV}"
IFS=',' read -r -a ENVS <<< "$ENVS_CSV"

mkdir -p "$OUT_ROOT"

START_TS="$(date +%Y%m%d_%H%M%S)"
MASTER_LOG="$OUT_ROOT/full_run_all_algos_projected_nonzero_theta_${START_TS}.log"

echo "[info] start_ts=$START_TS" | tee -a "$MASTER_LOG"
echo "[info] n_steps=$N_STEPS n_runs=$N_RUNS threads=$THREADS t0=$T0" | tee -a "$MASTER_LOG"
echo "[info] out_root=$OUT_ROOT" | tee -a "$MASTER_LOG"
echo "[info] envs=$ENVS_CSV" | tee -a "$MASTER_LOG"
echo "[info] base_values=$BASE_VALUES" | tee -a "$MASTER_LOG"
echo "[info] schedules=$SCHEDULES" | tee -a "$MASTER_LOG"
echo "[info] projections=$PROJECTIONS" | tee -a "$MASTER_LOG"

python3 - "$BASE_VALUES" "$SCHEDULES" "$PROJECTIONS" "${#ENVS[@]}" <<'PY' | tee -a "$MASTER_LOG"
import sys

def count_csv(s: str) -> int:
    return len([x for x in s.split(",") if x.strip()])

base_values = sys.argv[1]
schedules = sys.argv[2]
projections = sys.argv[3]
n_envs = int(sys.argv[4])

n_c = count_csv(base_values)
n_s = count_csv(schedules)
n_p = count_csv(projections)
total = n_envs * n_c * n_s * n_p

print(f"[info] expected_rows_per_env={n_c*n_s*n_p} (c={n_c}, schedules={n_s}, projections={n_p})")
print(f"[info] expected_total_rows_all_envs={total}")
PY

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
    --schedules "$SCHEDULES" \
    --projections "$PROJECTIONS" \
    --t0 "$T0" \
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

  python3 - "$manifest_path" "$env" "$BASE_VALUES" "$SCHEDULES" "$PROJECTIONS" <<'PY' | tee -a "$MASTER_LOG"
import csv
import math
import sys

manifest_path = sys.argv[1]
env = sys.argv[2]
base_values = sys.argv[3]
schedules = sys.argv[4]
projections = sys.argv[5]

def count_csv(s: str) -> int:
    return len([x for x in s.split(",") if x.strip()])

with open(manifest_path, "r", newline="", encoding="utf-8") as f:
    rows = list(csv.DictReader(f, delimiter="\t"))

if not rows:
    print(f"[error] empty manifest for {env}: {manifest_path}")
    sys.exit(1)

rows_per_case = count_csv(base_values) * count_csv(schedules) * count_csv(projections)
case_ids = sorted({r.get("case_id", "") for r in rows if r.get("case_id", "")})
n_cases = len(case_ids)
expected_rows = rows_per_case * n_cases
if n_cases <= 0:
    print(f"[error] no case_id found in manifest for {env}: {manifest_path}")
    sys.exit(1)

if len(rows) != expected_rows:
    print(
        f"[error] unexpected manifest row count for {env}: "
        f"got={len(rows)} expected={expected_rows} (cases={n_cases}, rows_per_case={rows_per_case}) "
        f"manifest={manifest_path}"
    )
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

scheds = sorted({r.get("schedule", "") for r in rows})
projs = sorted({r.get("projection", "") for r in rows})
print(
    f"[check] {env} rows={len(rows)} cases={n_cases} rows_per_case={rows_per_case} "
    f"theta_star_norm>0 confirmed: min={min(vals):.12g}, max={max(vals):.12g}"
)
print(f"[check] {env} schedules={','.join(scheds)} projections={','.join(projs)}")
PY
done

echo "[info] all environments finished with theta_star_norm > 0 and manifest-count checks passed" | tee -a "$MASTER_LOG"
