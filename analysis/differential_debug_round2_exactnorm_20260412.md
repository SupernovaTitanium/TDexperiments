# Differential Debugging Round 2: exact per-step theta-norm recomputation

## Goal

Test whether the remaining exactness gap between the current fixed source and the old baseline is primarily caused by the incremental update

```cpp
theta_n2 += 2 * beta * dot_phi + beta^2 * ||phi_s||^2
```

rather than by aggregation.

## Method

Built a temporary binary:

- source base: current [cpp/tdx.cpp](/home/leew0a/codex/TDfullexperiments/cpp/tdx.cpp)
- one local modification only:

```cpp
theta_n2 = std::inner_product(w.begin(), w.end(), w.begin(), 0.0);
```

at every step immediately after updating `w`.

Binary location:

- `/tmp/tdx_exactnorm`

Benchmark matrix:

- envs: `toyexample`, `E10`
- schedules: `theory,theory_log2,constant_omega,constant,inv_t,inv_sqrt_t,inv_t_2_3,inv_omega_t`
- projections: `none,oracle,upper`
- `c = 1e-2`
- `n_steps = 1e6`
- `n_runs = 40`
- `threads = 40`

## Exact output directories

- toyexample exact-norm:
  `/tmp/tdx_bench_toy_e10_fixcheck_20260412/out_exactnorm_toyexample/toyexample_20260412_005455`
- E10 exact-norm:
  `/tmp/tdx_bench_toy_e10_fixcheck_20260412/out_exactnorm_E10/E10_20260412_005455`

## Result summary

### Comparison against old baseline

#### toyexample

Current fixed source:

- `runs_diff = 58 / 96`
- `agg_diff = 92 / 96`

Exact-norm variant:

- `runs_diff = 9 / 96`
- `agg_diff = 79 / 96`

#### E10

Current fixed source:

- `runs_diff = 67 / 96`
- `agg_diff = 94 / 96`

Exact-norm variant:

- `runs_diff = 6 / 96`
- `agg_diff = 91 / 96`

## Interpretation

This is strong evidence that the unresolved run-level exactness gap is dominated by the incremental `theta_n2` optimization.

In other words:

- aggregation fixes alone were not enough
- exact per-step norm recomputation removes almost all remaining `runs_case` mismatches

## Residual run-level differences after exact-norm

### toyexample

Only `9` run files still differ, and all are tiny final-objective tails:

- `8` files differ in `final_obj_A, final_obj_D`
- `1` file differs only in `final_obj_A`

Worst observed magnitude:

- about `1e-8`

So there is no remaining meaningful `theta_norm / max_theta / clip_count` mismatch in toyexample once exact per-step norm recomputation is used.

### E10

Only `6` run files still differ, and all are tiny final-objective tails:

- `5` files differ in `final_obj_A, final_obj_D`
- `1` file differs only in `final_obj_A`

Worst observed magnitude:

- about `1e-13`

So the remaining run-level mismatch in E10 is also reduced to negligible floating tails.

## Residual agg-level differences after exact-norm

### toyexample

- `agg_diff = 79 / 96`
- breakdown:
  - `mean_only = 4`
  - `std_only = 43`
  - `mixed = 32`

### E10

- `agg_diff = 91 / 96`
- breakdown:
  - `mean_only = 1`
  - `std_only = 68`
  - `mixed = 22`

## Why agg differences remain high

The remaining `agg_case` mismatches are mostly expected, for two reasons:

1. the current source intentionally uses numerically stable variance aggregation (Welford), so it no longer reproduces the old baseline's unstable `std_*` artifacts
2. the current source also uses strict finite filtering, so mixed finite/inf checkpoints are aggregated differently from the old baseline

So at this point the large number of `agg_case` differences should not be interpreted as unresolved simulation bugs.

## Main conclusion

The second differential-debug round isolates the last important unresolved simulation-side issue:

- **incremental `theta_n2` maintenance is the dominant remaining source of run-level mismatch**

If exact reproducibility relative to the old baseline is important, then the right change is:

- replace incremental `theta_n2` maintenance with exact per-step recomputation in the production source

If raw speed is more important than exact baseline agreement, then keeping the incremental update is still a legitimate tradeoff, but it should be treated as an approximation that changes results.
