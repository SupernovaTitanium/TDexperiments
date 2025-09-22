# TD Threshold (Julia) — Usage Guide

Fast Julia implementation of semi-gradient TD(0) on a ToyExample MDP.

## Requirements

- Julia 1.11
- Optional for plots: PyPlot.jl

Install PyPlot once if you want PNG plots:

```
julia -e "using Pkg; Pkg.add(\"PyPlot\")"
```

## Files

- `TDThreshold.jl`: Core types and algorithms (ASCII identifiers only)
- `td_threshold_theory_sweep.jl`: CLI runner for theory-schedule c-sweep (decreasing step size).
- `plot_divergence.jl`: Reads CSVs, groups by eigen/omega, and generates analysis + learning-curve plots. Also produces best-per-eigen combined learning curves and a compact c-grid.

## c-Sweep (theory schedule)

Run a c-sweep with decreasing step sizes (theory schedule):

```
julia -t auto td_threshold_theory_sweep.jl --n_steps 10000000 --n_runs 48 

```






