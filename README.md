# TD Threshold — C++ Engine + Python Plots

This repository now includes a high-performance C++ implementation of the TD experiments under `cpp/`, with Python plotting scripts under `scripts/`.

Legacy Julia scripts are still present for reference and historical comparison, but the recommended execution path is now:

1. Run sweep/experiments with `cpp/tdx`
2. Plot + report with the unified Python v2 pipeline
   - `scripts/plot_suite_v2.py`
   - `scripts/generate_embedded_report_v2.py`

## Quick Start (C++)

Build:

```bash
make -C cpp
```

Run a sweep (example):

```bash
./cpp/tdx sweep \
  --env E4 \
  --set eps1=1e-3 \
  --set eps2=1e-2 \
  --base_values 1e-3,1e-2,1e-1,1 \
  --schedules theory,theory_log2,inv_t,inv_sqrt_t,inv_t_2_3,inv_omega_t,constant_omega,constant \
  --projections none,oracle,upper \
  --n_steps 1000000 \
  --n_runs 32 \
  --outdir td_cxx_logs
```

Or run from a checked-in config:

```bash
./cpp/tdx sweep --config configs/study_e4.cfg
```

Generate plots:

```bash
UV_CACHE_DIR=/tmp/uv-cache \
MPLCONFIGDIR=/home/leew0a/codex/TDfullexperiments/.mplconfig \
uv run --python ./.venv_plot/bin/python python scripts/plot_suite_v2.py \
  --run-dir td_cxx_logs/<env>_<timestamp>

UV_CACHE_DIR=/tmp/uv-cache \
MPLCONFIGDIR=/home/leew0a/codex/TDfullexperiments/.mplconfig \
uv run --python ./.venv_plot/bin/python python scripts/generate_embedded_report_v2.py \
  --root td_cxx_logs/<env>_<timestamp>
```

Notes:
- The plotting environment is `./.venv_plot` (managed as the project plotting Python env).
- In sandboxed runs, set `UV_CACHE_DIR` to a writable location (for example `/tmp/uv-cache`).
- `cpp/tdx --plot_python` now prefers `./.venv_plot/bin/python` automatically.
- You can override the plotting interpreter via `TDPLOT_PYTHON=/path/to/python`.

`plot_suite_v2.py` is the single plotting entrypoint for C++ outputs. It reads `manifest.tsv` and supports variable numbers of:

- instances per env (`case_id` count)
- omega levels (no hard-coded 4-omega assumption)
- methods (`schedule x projection`)
- `c` values

v2 plot families on C++ output:

- `bestcurves_by_c` with best `c` per method (metric `D` and `D+A`)
- per-method final grids (rows by omega, columns ratio/divergence/`D`/`D+A`)
- per-method learning-curve-by-`c` grids (`D`, `D+A`)
- per-method omega-vs-final-error scatter (`D`, `D+A`)
- per-omega figures that overlay all methods at each method's best `c` (`D`, `D+A`)

Python plotting dependencies:

```bash
python3 -m pip install matplotlib
```

Key algorithm support in C++:

- Unprojected TD(0): `theory`, `constant`, `inv_t`, `inv_sqrt_t`, `inv_omega_t`
- Additional schedules: `theory_log2`, `inv_t_2_3`, `constant_omega`
- Projected TD(0):
  - oracle radius: `R = ||theta*||_2`
  - upper-bound radius: `R = 2*r_max / (sqrt(omega) * (1-gamma)^(3/2))`

Output schema (`manifest.tsv`) includes:

- `algorithm`, `schedule`, `projection`, `projection_radius`
- `omega`, `kappa`, `tau_proxy`
- `agg_file`, `run_file` for downstream plotting

## Full Study Requested (1e7 steps, 48 Monte Carlo, toyexample + E1..E10)

Run the exact full sweep used in this project update:

```bash
make -C cpp
./scripts/run_full_1e7_theory_all_envs.sh
```

Defaults in `scripts/run_full_1e7_theory_all_envs.sh`:

- environments: `toyexample,E1,E2,...,E10`
- `n_steps=10000000`
- `n_runs=48`
- `threads=48`
- schedule/projection: `theory` + `none`
- scale grid (`base_values`): `1e-5` to `1e3` with half-decade spacing (17 values)
- output root: `td_cxx_logs_full_1e7`

Produced artifacts:

- per-environment run folders: `td_cxx_logs_full_1e7/<env>_<timestamp>/`
- full log: `td_cxx_logs_full_1e7/full_run_<timestamp>.log`
- each `manifest.tsv` row has one `(env, c)` combination and points to:
  - aggregate curve file (`agg_file`)
  - per-MC run file (`run_file`, 48 rows)

## Full 1e9 Study (All Stepsizes + Projected TD, 48 Monte Carlo, toyexample + E1..E10)

Run the complete C++ sweep:

```bash
make -C cpp
./scripts/run_full_1e9_all_algos_projected_all_envs.sh
```

Defaults in `scripts/run_full_1e9_all_algos_projected_all_envs.sh`:

- environments: `toyexample,E1,E2,...,E10`
- `n_steps=1000000000`
- `n_runs=48`
- `threads=48`
- schedules: `theory,theory_log2,inv_t,inv_sqrt_t,inv_t_2_3,inv_omega_t,constant_omega,constant`
- projections: `none,oracle,upper`
- scale grid (`base_values`): `1e-5` to `1e3` with half-decade spacing (17 values, shared across all schedules/projections)
- output root: `td_cxx_logs_full_1e9_all_algos_projected_nonzero_theta`

Total sweep size:

- per environment: `17 * 8 * 3 = 408` combinations
- full run (`toyexample + E1..E10`): `11 * 408 = 4488` combinations
- total MC trajectories: `4488 * 48 = 215424`

Progress monitor:

```bash
scripts/monitor_full_run_progress.py \
  --root /home/leew0a/codex/TDfullexperiments/td_cxx_logs_full_1e9_all_algos_projected_nonzero_theta
```

## Julia vs C++ Approximation Check

To verify Julia and C++ produce close results on matched settings, run a verification slice:

```bash
# 1) C++ slice (same env set, 48 runs, smaller steps for practical turnaround)
BASE_VALUES='1e-5,1e-3,1e-1,1,1e3' \
N_STEPS=200000 \
N_RUNS=48 \
THREADS=48 \
OUT_ROOT=td_cxx_logs_verify48 \
./scripts/run_full_1e7_theory_all_envs.sh

# 2) Julia compact summary
julia -t auto --project=.julia_env scripts/julia_theory_summary.jl \
  --n_steps 200000 \
  --n_runs 48 \
  --c_values 1e-5,1e-3,1e-1,1,1e3 \
  --out verification/julia_theory_summary_48.tsv

# 3) Extract C++ compact summary
python3 scripts/extract_cpp_theory_summary.py \
  --root td_cxx_logs_verify48 \
  --out verification/cpp_theory_summary_48.tsv

# 4) Compare tables
python3 scripts/compare_cpp_julia_summary.py \
  --cpp verification/cpp_theory_summary_48.tsv \
  --julia verification/julia_theory_summary_48.tsv \
  --out verification/cpp_vs_julia_compare_48.tsv
```

Current comparison snapshot after RNG alignment (legacy 13-env artifact `verification/cpp_vs_julia_compare_48_rng.tsv`, 65 matched rows):

- maxima:
  - `omega_rel_max=2.1713e-12`
  - `kappa_rel_max=1.5998e-12`
  - `finalD_rel_max=0`
  - `finalA_rel_max=0`
  - `div_abs_max=0`

Interpretation notes:

- Julia/C++ now use the same deterministic `SplitMix64` RNG stream and identical seed-mixing formula.
- aggregation excludes non-finite checkpoints in both implementations, so divergence handling is aligned.

## Full Julia vs C++ Check (1e7, 48 runs, 11 envs, 17 scales)

Full comparison command set:

```bash
# C++ full sweep
N_STEPS=10000000 N_RUNS=48 THREADS=48 OUT_ROOT=td_cxx_logs_full_1e7_rng \
./scripts/run_full_1e7_theory_all_envs.sh

# Julia full summary
julia -t auto --project=.julia_env scripts/julia_theory_summary.jl \
  --n_steps 10000000 \
  --n_runs 48 \
  --c_values 1e-5,3.16227766017e-5,1e-4,3.16227766017e-4,1e-3,3.16227766017e-3,1e-2,3.16227766017e-2,1e-1,3.16227766017e-1,1,3.16227766017,1e1,3.16227766017e1,1e2,3.16227766017e2,1e3 \
  --out verification/julia_theory_summary_1e7_48_rng.tsv

# Extract + compare
python3 scripts/extract_cpp_theory_summary.py \
  --root td_cxx_logs_full_1e7_rng \
  --out verification/cpp_theory_summary_1e7_48_rng.tsv
python3 scripts/compare_cpp_julia_summary.py \
  --cpp verification/cpp_theory_summary_1e7_48_rng.tsv \
  --julia verification/julia_theory_summary_1e7_48_rng.tsv \
  --out verification/cpp_vs_julia_compare_1e7_48_rng.tsv
```

Expected rows with the current 11-env default are `11 * 17 = 187`.
The checked-in comparison artifact is currently the legacy 13-env file (`verification/cpp_vs_julia_compare_1e7_48_rng.tsv`, 221 rows), with maxima:

- `omega_rel_max=2.1713e-12`
- `kappa_rel_max=1.5998e-12`
- `finalD_rel_max=1.6117e-10`
- `finalA_rel_max=2.2288e-10`
- `div_abs_max=0`

These are floating-point roundoff scale differences (absolute error up to about `1e-15`), not algorithmic mismatches.

# Legacy Julia Usage (Reference)

Finite-state Julia implementation of semi-gradient TD(0) with a generic environment layer.

The repo now supports:

- the original `toyexample` setup
- candidate environments `E1` through `E10` (renumbered after removing legacy `E3` and `E7`) from [example.md](./example.md)
- fixed parameters via `--set key=value`
- parameter sweeps via `--sweep key=v1,v2,...`
- manifest-driven plotting for new runs while keeping legacy filename parsing for old result folders
- static HTML reports with TD-instance summaries and inline plots

## Requirements

- Julia 1.11.8
- Optional for plots and PNG export: PyPlot.jl

Install PyPlot once if you want EPS plots, PNG companions, or HTML reports that auto-fill missing PNGs:

```bash
julia -e "using Pkg; Pkg.add(\"PyPlot\")"
```

## Files

- `TDThreshold.jl`: Core types, generic finite-state environments, and builders for `toyexample` + `E1..E10`
- `td_threshold_theory_sweep.jl`: CLI runner for theory-schedule `c` sweeps across environment cases
- `plot_divergence.jl`: Plotting pipeline; prefers `manifest.tsv` for new runs and falls back to legacy filename parsing
- `export_plots_png.jl`: Re-runs plotting and also saves PNG companions when possible
- `generate_run_reports.jl`: Builds static HTML reports (`report.html`) for each run and a root `index.html`
- `td_instance_report_overrides.jl`: Instance catalog and report layout overrides used by the HTML viewer
- `example.md`: Environment definitions and the intended stress-test interpretations

## Basic Usage

Original toyexample workflow:

```bash
julia -t auto td_threshold_theory_sweep.jl --n_steps 10000000 --n_runs 48
```

This still defaults to the old toyexample scale sweep.

Single non-toy environment case:

```bash
julia -t auto td_threshold_theory_sweep.jl \
  --env E4 \
  --set eps1=1e-3 \
  --set eps2=1e-2 \
  --set reward_mode=signed \
  --c_values 1e0,1e2,1e4
```

Sweep an environment parameter:

```bash
julia -t auto td_threshold_theory_sweep.jl \
  --env E9 \
  --set m=64 \
  --set alpha_max=1.57079632679 \
  --sweep eps1=1e-2,1e-3,1e-4 \
  --c_values 1e0,1e2,1e4
```

Write CSV and `manifest.tsv` only:

```bash
julia -t auto td_threshold_theory_sweep.jl \
  --env E4 \
  --set eps1=1e-3 \
  --set eps2=1e-2 \
  --skip_plots
```

## Outputs

Each run directory contains:

- aggregated CSV files per `(case, c)`
- per-run CSV files per `(case, c)`
- `manifest.tsv` describing the cases, parameter values, and file mappings
- optionally `plots/` with EPS figures; omit plotting with `--skip_plots`

Output directory behavior:

- default base directory is `td_divergence_logs`
- if `--outdir` is omitted, the runner writes to `td_divergence_logs/<env>_<timestamp>`
- if `--outdir` is provided and its basename already starts with `<env>_`, it is treated as the final run directory
- otherwise the runner still creates `--outdir/<env>_<timestamp>`

## Plotting

Re-render plots for an existing output directory:

```bash
julia plot_divergence.jl --dir td_divergence_logs/E4_YYYYMMDD_HHMMSS
```

Generated figures include:

- per-case final analysis plots
- learning-curve grids for the `D` and `A` objectives
- full and compact grid summaries
- best-curve overlays across cases

Generate PNG companions for an existing run:

```bash
julia export_plots_png.jl td_divergence_logs/E4_YYYYMMDD_HHMMSS
```

## HTML Reports

Build a static local viewer for all runs under `td_divergence_logs`:

```bash
julia generate_run_reports.jl --root td_divergence_logs
```

This generates:

- `td_divergence_logs/index.html`: grouped run index
- `<run_dir>/report.html`: per-run report with inline images, parameter tables, and TD-instance summaries

The report generator will try to create missing PNG files automatically by calling `export_plots_png.jl` when a run only has EPS plots.
