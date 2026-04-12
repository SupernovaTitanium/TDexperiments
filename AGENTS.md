# AGENTS.md

Repo-local instructions for Codex working in `/home/leew0a/codex/TDfullexperiments`.

This file is intentionally specific to this repository. It supplements the user's global guidance.

## Scope and Primary Workflow

Use the C++ engine as the default implementation path.

Primary path:

1. build with `make -C cpp`
2. run experiments with `./cpp/tdx`
3. generate plots with `scripts/plot_suite_v2.py`
4. generate self-contained HTML with `scripts/generate_embedded_report_v2.py`

Do not default to the legacy Julia pipeline unless the task explicitly requires historical Julia behavior or Julia-vs-C++ comparison.

## Source of Truth

Core files:

- `cpp/tdx.cpp`: TD engine and sweep CLI
- `cpp/Makefile`: build flags and targets
- `scripts/plot_suite_v2.py`: plotting source of truth for C++ outputs
- `scripts/generate_embedded_report_v2.py`: embedded HTML report generator
- `manifest.tsv` inside each run directory: plotting/report source of truth

If a task touches semantics, read the current implementation in `cpp/tdx.cpp` before assuming behavior from older reports.

## Non-Negotiable Constraint: Exactness First

The default branch is now the exactness-preserving accelerated version.

That means:

- preserve deterministic RNG behavior
- preserve `manifest.tsv` schema
- preserve `runs_case_*.csv` outputs
- preserve `agg_case_*.csv` outputs

Do not reintroduce "fast but not exact" optimizations as the default implementation.

Specifically, if you experiment with performance changes, do not keep them by default unless exactness revalidation passes.

Historical debugging notes are in:

- `analysis/final_runs_mismatch_debug_20260412.md`
- `analysis/final_exact_revalidation_20260412.md`
- `analysis/incremental_norm_removal_20260412.md`
- `analysis/differential_debug_toyexample_E10_20260412.md`

## Build and Run Commands

Build:

```bash
make -C cpp
```

Help:

```bash
./cpp/tdx --help
./cpp/tdmix_kstep --help
```

Representative smoke run:

```bash
./cpp/tdx sweep \
  --env E5 \
  --set reward_mode=launch \
  --set rho=1.0 \
  --base_values 1e-2 \
  --schedules theory,theory_log2,constant_omega,constant,inv_t,inv_sqrt_t,inv_t_2_3,inv_omega_t \
  --projections none,oracle,upper \
  --n_steps 100000 \
  --n_runs 8 \
  --threads 8 \
  --outdir /tmp/tdx_smoke
```

Representative exactness-preserving benchmark references:

- `analysis/perf_exact_vs_baseline_1e6_c9_20260412.md`
- `analysis/large_benchmark_all11_20260411.md`

## Plotting Environment

Always prefer the checked-in plotting environment:

- Python: `./.venv_plot/bin/python`
- `uv` wrapper: `uv run --python ./.venv_plot/bin/python python ...`
- `./cpp/tdx --plot_python` auto-detects `./.venv_plot/bin/python` before falling back to `python3`

In sandboxed runs, set:

- `UV_CACHE_DIR=/tmp/uv-cache`
- `MPLCONFIGDIR=/home/leew0a/codex/TDfullexperiments/.mplconfig`

Representative commands:

```bash
UV_CACHE_DIR=/tmp/uv-cache \
MPLCONFIGDIR=/home/leew0a/codex/TDfullexperiments/.mplconfig \
uv run --python ./.venv_plot/bin/python python scripts/plot_suite_v2.py --run-dir <run-dir>
```

```bash
UV_CACHE_DIR=/tmp/uv-cache \
MPLCONFIGDIR=/home/leew0a/codex/TDfullexperiments/.mplconfig \
uv run --python ./.venv_plot/bin/python python scripts/generate_embedded_report_v2.py --root <run-root>
```

## Environment and Case Structure

Current default study shape:

- env families: `toyexample`, `E1` through `E10`
- default case count per env family: `4`
- default sweep parameters:
  - `toyexample`, `E4`, `E5`, `E6`, `E7`: `feature_omega_beta = {1e-3, 1e-2, 1e-1, 1.0}`
  - `E1`, `E2`, `E3`, `E8`, `E9`, `E10`: `eps2 = {1e-4, 1e-2, 1e-1, 1.0}`
- these defaults typically induce four omega levels, but plotting/report code must still support variable case counts
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

Do not hard-code a 4-omega assumption in plotting or reporting code. The v2 plot/report pipeline is intended to support variable numbers of cases.

## When Modifying `cpp/tdx.cpp`

Required checks depend on the change.

### If the change is superficial

Examples:

- comments
- help text
- minor logging changes

Do:

1. `make -C cpp`
2. run one small smoke sweep if behavior could plausibly be affected

### If the change touches simulation semantics, RNG, aggregation, projection, stepsizes, or output schema

Do all of the following:

1. rebuild: `make -C cpp`
2. run a smoke sweep
3. compare current outputs against the known baseline on at least representative cases
4. if exactness is claimed, verify `manifest.tsv`, `runs_case_*.csv`, and `agg_case_*.csv`
5. write a short report in `analysis/` if the debugging or benchmark work is substantive

Hard representative cases for debugging are historically `toyexample` and `E10`.

## Long Runs and Benchmarks

For transient benchmarks, prefer writing outputs under `/tmp`.

For checked-in final artifacts, use:

- `analysis/` for benchmark/debugging reports
- `verification/` for instance summaries and table-based comparisons

When reporting a benchmark, record:

- command/configuration
- compared binaries
- per-env timing table
- total timing
- exactness result
- output root

## Legacy Julia Code

Julia remains in-repo for reference only.

Important Julia files:

- `TDThreshold.jl`
- `td_threshold_theory_sweep.jl`
- `plot_divergence.jl`
- `generate_run_reports.jl`

Use Julia only if the task explicitly calls for:

- comparison with historical Julia behavior
- regeneration of legacy Julia figures
- validation against older Julia outputs

## Done Criteria for Codex

A change is not done just because code compiles.

Minimum done criteria:

1. code builds
2. the relevant run path executes
3. if semantics changed, exactness is checked at the right level
4. if plots/reports changed, at least one plot/report generation path is exercised
5. outputs and conclusions are written to a stable artifact when the work is substantial

## Practical Defaults

- prefer `rg` for code search
- prefer `apply_patch` for focused edits
- do not delete experiment logs or reports unless explicitly asked
- do not overwrite user-run result folders casually
- if a benchmark is expensive, use `/tmp` unless the user explicitly wants checked-in outputs
