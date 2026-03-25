# TD Threshold (Julia) — Usage Guide

Finite-state Julia implementation of semi-gradient TD(0) with a generic environment layer.

The repo now supports:

- the original `toyexample` setup
- candidate environments `E1` through `E12` from [example.md](./example.md)
- fixed parameters via `--set key=value`
- parameter sweeps via `--sweep key=v1,v2,...`
- manifest-driven plotting for new runs while keeping legacy filename parsing for old result folders

## Requirements

- Julia 1.11.8
- Optional for plots: PyPlot.jl

Install PyPlot once if you want EPS plots:

```bash
julia -e "using Pkg; Pkg.add(\"PyPlot\")"
```

## Files

- `TDThreshold.jl`: Core types, generic finite-state environments, and builders for `toyexample` + `E1..E12`
- `td_threshold_theory_sweep.jl`: CLI runner for theory-schedule `c` sweeps across environment cases
- `plot_divergence.jl`: Plotting pipeline; prefers `manifest.tsv` for new runs and falls back to legacy filename parsing
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

## Outputs

Each run directory contains:

- aggregated CSV files per `(case, c)`
- per-run CSV files per `(case, c)`
- `manifest.tsv` describing the cases, parameter values, and file mappings
- `plots/` with EPS figures

Default output root is `td_divergence_logs/<env>_<timestamp>` unless `--outdir` is provided.

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
