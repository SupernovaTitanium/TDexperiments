# TD Threshold (Julia) — Usage Guide

Fast Julia implementation of semi-gradient TD(0) on a ToyExample MDP.

## Requirements

- Julia 1.11.8
- Optional for plots: PyPlot.jl

Install PyPlot once if you want EPS plots:

```
julia -e "using Pkg; Pkg.add(\"PyPlot\")"
```

## Files

- `TDThreshold.jl`: Core types and algorithms 
- `td_threshold_theory_sweep.jl`: CLI runner for theory-schedule c-sweep 
- `plot_divergence.jl`: Reads CSVs, groups by eigen/omega, and generates EPS plots.

## c-Sweep (theory schedule)

Run a c-sweep with decreasing step sizes (theory schedule):

```
julia -t auto td_threshold_theory_sweep.jl --n_steps 10000000 --n_runs 48 

```

Paper-ready c-sweep plots are saved under `<outdir>/plots` (default: `td_divergence_logs/<env>_<timestamp>/plots`), e.g. `toyexample__compact__rows-c.eps`.



