# TD Threshold Experiments

Finite-state TD(0) experiment repository with:

- a C++ experiment engine in `cpp/`
- Python plotting/report generation in `scripts/`
- legacy Julia implementations kept for reference and historical comparison

The recommended workflow is now:

1. run experiments with `./cpp/tdx`
2. generate plots with `scripts/plot_suite_v2.py`
3. generate a self-contained HTML report with `scripts/generate_embedded_report_v2.py`

## Current Status

`main` now points to the exactness-preserving accelerated C++ engine.

This version keeps outputs byte-identical to the earlier stable baseline on the checked benchmark suites while running materially faster. See:

- `analysis/final_exact_revalidation_20260412.md`
- `analysis/perf_exact_vs_baseline_1e6_c9_20260412.md`
- `analysis/large_benchmark_all11_20260411.md`

## Repository Layout

- `cpp/tdx.cpp`: main TD experiment engine
- `cpp/tdmix_kstep.cpp`: k-step Dobrushin contraction / mixing-time utility
- `cpp/Makefile`: C++ build entrypoint
- `scripts/plot_suite_v2.py`: main plot generator for C++ outputs
- `scripts/generate_embedded_report_v2.py`: self-contained HTML report generator
- `scripts/run_full_*.sh`: checked-in experiment launchers
- `analysis/`: debugging, benchmarking, and exactness reports
- `verification/`: instance summaries, comparison tables, and verification artifacts
- `configs/`: example config-driven sweeps
- `README.md`: human-oriented repo guide
- `AGENTS.md`: repo-local instructions for Codex and future maintenance

## Supported Experiment Structure

The current C++ engine supports:

- environments: `toyexample`, `E1`, `E2`, ..., `E10`
- default 4-case parameter sweep per environment family
  - `toyexample`, `E4`, `E5`, `E6`, `E7`: `feature_omega_beta = {1e-3, 1e-2, 1e-1, 1.0}`
  - `E1`, `E2`, `E3`, `E8`, `E9`, `E10`: `eps2 = {1e-4, 1e-2, 1e-1, 1.0}`
  - these defaults are the current source of the four benchmarked omega levels
- schedules:
  - `theory`
  - `theory_log2`
  - `inv_t`
  - `inv_sqrt_t`
  - `inv_t_2_3`
  - `inv_omega_t`
  - `constant_omega`
  - `constant`
- projections:
  - `none`
  - `oracle`
  - `upper`

Projection radii:

- `oracle`: `R = ||theta*||_2`
- `upper`: `R = 2*r_max / (sqrt(omega) * (1-gamma)^(3/2))`

## Build

Build the C++ binaries:

```bash
make -C cpp
```

Useful binaries:

- `cpp/tdx`: TD experiment engine
- `cpp/tdmix_kstep`: k-step Dobrushin mixing estimator

Show CLI help:

```bash
./cpp/tdx --help
./cpp/tdmix_kstep --help
```

## Quick Start

Run one sweep directly:

```bash
./cpp/tdx sweep \
  --env E4 \
  --set reward_mode=single-site \
  --set rho=1.0 \
  --base_values 1e-3,1e-2,1e-1,1 \
  --schedules theory,theory_log2,inv_t,inv_sqrt_t,inv_t_2_3,inv_omega_t,constant_omega,constant \
  --projections none,oracle,upper \
  --n_steps 1000000 \
  --n_runs 40 \
  --threads 40 \
  --outdir td_cxx_logs
```

Run from a config file:

```bash
./cpp/tdx sweep --config configs/study_e4.cfg
```

## Plotting and Report Generation

Use the dedicated plotting environment in `./.venv_plot`.

In this repository, the safe plotting command is:

```bash
UV_CACHE_DIR=/tmp/uv-cache \
MPLCONFIGDIR=/home/leew0a/codex/TDfullexperiments/.mplconfig \
uv run --python ./.venv_plot/bin/python python scripts/plot_suite_v2.py \
  --run-dir td_cxx_logs/<env>_<timestamp>
```

Generate the embedded HTML report:

```bash
UV_CACHE_DIR=/tmp/uv-cache \
MPLCONFIGDIR=/home/leew0a/codex/TDfullexperiments/.mplconfig \
uv run --python ./.venv_plot/bin/python python scripts/generate_embedded_report_v2.py \
  --root td_cxx_logs/<env>_<timestamp>
```

Notes:

- prefer `./.venv_plot/bin/python` for plotting work
- in sandboxed runs, use writable `UV_CACHE_DIR`, usually `/tmp/uv-cache`
- `./cpp/tdx --plot_python` auto-detects `./.venv_plot/bin/python` before falling back to `python3`
- `plot_suite_v2.py` supports variable numbers of cases, omega levels, methods, and `c` values
- `generate_embedded_report_v2.py` picks the latest run directory per environment when given a root with multiple runs

## Checked-In Experiment Launchers

Representative launchers:

- `scripts/run_full_1e6_all_algos_44instances_n36.sh`
- `scripts/run_full_1e7_theory_all_envs.sh`
- `scripts/run_full_1e9_all_algos_projected_all_envs.sh`
- `scripts/monitor_full_run_progress.py`

These scripts are useful references even when you override `N_STEPS`, `N_RUNS`, `THREADS`, `BASE_VALUES`, or output roots via environment variables.

## Output Format

Each `./cpp/tdx sweep` run creates a timestamped run directory containing at least:

- `manifest.tsv`
- `runs_case_*.csv`
- `agg_case_*.csv`

`manifest.tsv` is the source of truth for downstream plotting and report generation. It records, among other fields:

- environment and case identifiers
- schedule / projection / algorithm metadata
- `omega`, `kappa`, `tau_proxy`
- output file paths for aggregate and per-run CSVs

## Exactness and Performance Policy

The current repository policy is:

- exactness comes before speed
- performance changes are acceptable only if they preserve baseline outputs
- if a speed optimization breaks `manifest.tsv`, `runs_case_*.csv`, or `agg_case_*.csv` exactness, it should not be kept as the default implementation

Recent exactness-preserving benchmark results:

- `analysis/perf_exact_vs_baseline_1e6_c9_20260412.md`
  - `1e6` steps, `11` env families, `4` omega cases, `8` schedules, `3` projections, `9` `c` values, `40` runs
  - overall speedup: about `3.0x`
- `analysis/final_exact_revalidation_20260412.md`
  - full exactness revalidation after optimization and debugging

## Julia Reference Path

Legacy Julia code remains in the repository for:

- comparison to the historical implementation
- theory-summary extraction
- reproducibility with older result folders

Main Julia files:

- `TDThreshold.jl`
- `td_threshold_theory_sweep.jl`
- `plot_divergence.jl`
- `generate_run_reports.jl`

Use Julia only when you explicitly need legacy behavior or Julia-vs-C++ comparison. For new experiments, prefer C++.

## Verification and Study Documents

Useful checked-in documents:

- `verification/summary_instance.md`
- `verification/detailed_td_instance_report_20260403.md`
- `verification/td_instance_summary_corrected_20260404.md`
- `plottable.md`
- `analysis/no_projection_theory_review_20260410.md`
- `analysis/no_projection_theory_summary_tables_20260410.md`

These files summarize instance definitions, plotting plans, and experiment conclusions.

## Minimal Maintenance Checklist

When changing the C++ engine:

1. rebuild with `make -C cpp`
2. run at least one smoke sweep with `./cpp/tdx sweep ...`
3. if simulation semantics changed, re-run an exactness comparison against the known baseline
4. if plotting code changed, regenerate at least one plot directory and one embedded report
5. record benchmark or debugging results in `analysis/` if the change is substantive
