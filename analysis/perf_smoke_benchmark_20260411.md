# Smoke Benchmark for `tdx.cpp` Performance Changes (2026-04-11)

## Goal
Measure the effect of the first hot-path optimizations applied to:
- [tdx.cpp](/home/leew0a/codex/TDfullexperiments/cpp/tdx.cpp)

Optimizations included in this pass:
1. compute `D` / `D+A` objective only at checkpoints, not every step
2. maintain `||theta_t||^2` incrementally
3. replace dense full-row transition scan with sparse support-row sampling

## Benchmark workload
Command shape:

```bash
./cpp/tdx sweep \
  --env E5 \
  --sweep feature_omega_beta=1.0 \
  --base_values 1e-2 \
  --schedules theory \
  --projections none \
  --n_steps 2000000 \
  --n_runs 32 \
  --threads <T> \
  --outdir <OUT>
```

Fixed workload details:
- environment: `E5`
- cases: `1`
- schedule: `theory`
- projection: `none`
- `c = 1e-2`
- `n_steps = 2e6`
- `n_runs = 32`
- thread counts tested: `1, 8, 16, 32`

Reason for this workload:
- `E5` has `d=20`, so the old every-step `O(d^2)` objective evaluation is expensive enough to expose the optimization clearly.
- `n_runs=32` lets multi-thread scaling show up.

## Raw timing results

| Threads | Baseline seconds | Optimized seconds | Speedup |
|---:|---:|---:|---:|
| 1 | 12.2062 | 2.2792 | 5.36x |
| 8 | 1.6365 | 0.3605 | 4.54x |
| 16 | 0.9188 | 0.2242 | 4.10x |
| 32 | 0.5914 | 0.1819 | 3.25x |

## Interpretation

| Observation | Meaning |
|---|---|
| Single-thread speedup is `5.36x` | The hot-path waste was real, not just an OpenMP artifact |
| Speedup remains above `3x` even at 32 threads | Optimization still matters in highly parallel sweeps |
| Absolute benefit is largest on low/moderate threads | Expected, because fixed OpenMP and I/O overhead become more visible at high thread counts |

## Output-difference check
I compared baseline vs optimized outputs for every tested thread count using:
- `manifest.tsv`
- `agg_*.csv`
- `runs_*.csv`

Comparison result for each thread count `1, 8, 16, 32`:

| Threads | `manifest.tsv` | `agg_*.csv` max abs diff | `agg_*.csv` max rel diff | `runs_*.csv` max abs diff | `runs_*.csv` max rel diff |
|---:|---|---:|---:|---:|---:|
| 1 | identical | 0 | 0 | 0 | 0 |
| 8 | identical | 0 | 0 | 0 | 0 |
| 16 | identical | 0 | 0 | 0 | 0 |
| 32 | identical | 0 | 0 | 0 | 0 |

Additional comparison counters:
- `diff_cells = 0`
- `nonfinite_mismatch = 0`
- `string_mismatch = 0`

So for this smoke workload, the optimized code is **exact-output identical** to the baseline.

## What changed in code
Primary hot-path changes were made in:
- [tdx.cpp:1505](/home/leew0a/codex/TDfullexperiments/cpp/tdx.cpp#L1505)
- [tdx.cpp:1519](/home/leew0a/codex/TDfullexperiments/cpp/tdx.cpp#L1519)

Key effect:
- objective evaluation no longer happens `2e6` times per run; it now happens only at checkpoints
- for `n_steps=1e8`, default checkpoint count is only about `692`, so the asymptotic savings are much larger for long runs

## Current conclusion
This first optimization pass is successful.

Safe claims:
1. the modified C++ runner is materially faster
2. the speedup persists across multiple thread counts
3. the smoke benchmark produced exactly identical output files

## Recommended next step
The next optimization pass should target:
1. schedule/projection specialization to remove per-step branch overhead
2. lower-allocation aggregation / online accumulation
3. optional build improvements (`-flto`, PGO)

I would postpone more aggressive RNG-path-changing ideas, such as alias sampling, until after these safer changes are benchmarked.
