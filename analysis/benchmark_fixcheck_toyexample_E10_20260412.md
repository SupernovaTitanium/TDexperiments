# toyexample + E10 full benchmark fix-check (2026-04-12)

## Goal

Re-run the full benchmark matrix for `toyexample` and `E10` only, comparing:

- baseline binary: `/tmp/tdx_bench_suite_20260411/tdx_baseline_d9c4dde`
- current fixed source: [cpp/tdx.cpp](/home/leew0a/codex/TDfullexperiments/cpp/tdx.cpp)

using the same benchmark settings as the earlier large benchmark.

## Commands used

For each env (`toyexample`, `E10`) and each binary (baseline, fixed):

- `base_values = 1e-2`
- `schedules = theory,theory_log2,constant_omega,constant,inv_t,inv_sqrt_t,inv_t_2_3,inv_omega_t`
- `projections = none,oracle,upper`
- `n_steps = 1e6`
- `n_runs = 40`
- `threads = 40`

Output root:

`/tmp/tdx_bench_toy_e10_fixcheck_20260412`

## Exact run directories

- toyexample baseline:
  `/tmp/tdx_bench_toy_e10_fixcheck_20260412/out_baseline_toyexample/toyexample_20260412_004401`
- toyexample fixed:
  `/tmp/tdx_bench_toy_e10_fixcheck_20260412/out_fixed_toyexample/toyexample_20260412_004401`
- E10 baseline:
  `/tmp/tdx_bench_toy_e10_fixcheck_20260412/out_baseline_E10/E10_20260412_004401`
- E10 fixed:
  `/tmp/tdx_bench_toy_e10_fixcheck_20260412/out_fixed_E10/E10_20260412_004401`

## High-level result

The answer is **no**: the old mismatches are **not fully consumed** if the criterion is exact agreement with the old baseline outputs across the full matrix.

However, the meaning of the remaining mismatches is important:

1. the previously identified `toyexample` / `E10` aggregation pathologies are now explained and locally fixed
2. many remaining differences are because the old baseline outputs were themselves numerically unstable or semantically inconsistent in aggregation
3. the current source still has a separate exactness gap relative to baseline in run-level `theta_n2`-related bookkeeping

## Summary table

### toyexample

- `manifest.tsv`: exact
- `runs_case_*.csv`: `58 / 96` differ
- `agg_case_*.csv`: `92 / 96` differ

Breakdown of differing `agg_case` files:

- `11` mean-only differences
- `23` std-only differences
- `58` mixed differences

### E10

- `manifest.tsv`: exact
- `runs_case_*.csv`: `67 / 96` differ
- `agg_case_*.csv`: `94 / 96` differ

Breakdown of differing `agg_case` files:

- `4` mean-only differences
- `24` std-only differences
- `66` mixed differences

## What improved

### Original target mismatch: toyexample `case0002 / inv_omega_t / upper`

Previously the characteristic failure was:

- baseline `std_max_theta = 1860225.54463`
- optimized `std_max_theta = 0`

After the projection bookkeeping fix, this exact pathology is gone. The remaining difference is now a tiny norm-dispersion tail:

- fixed output: `std_max_theta = 0.0201465577472`

So the structural bug `theta_n2 = proj_R2` was real and is fixed.

### Original target mismatch: E10 `case0003 / inv_omega_t / none`

Previously the characteristic failure was huge fake variance:

- baseline `std_A = 1.03498390482e+16`
- optimized `std_D = 1.01519683032e+16`

After the Welford + strict-finite fixes, the fixed output becomes:

- `std_D = 0`
- `std_A = 0`
- `std_max_theta = 0`

This matches the per-run trace conclusion that the checkpoint values are effectively identical and the old `std_*` values were numerical artifacts.

## What still does not match

### 1. run-level differences remain widespread

This is the main unresolved issue.

#### toyexample run diffs are mostly:

- `final_theta_norm` only: `34` files
- `final_obj_A, final_obj_D`: `12` files
- `final_obj_A, final_obj_D, final_theta_norm`: `4` files

Largest example:

- `runs_case_0001__sched_inv_t__proj_none__c_1.000e-02.csv`
- worst `final_theta_norm` difference: `3560`

#### E10 run diffs are mostly:

- `final_theta_norm` only: `31` files
- `final_theta_norm, max_theta_norm, ratio_max_over_theta_star_sq`: `12` files
- `final_theta_norm, max_theta_norm`: `6` files
- `final_obj_A, final_obj_D`: `6` files
- `max_proj_clip_count`: `3` files

Largest example:

- `runs_case_0004__sched_constant__proj_oracle__c_1.000e-02.csv`
- `max_proj_clip_count`: baseline `110955`, fixed `109060`

### Interpretation

This pattern strongly suggests the remaining exactness gap is **not** in aggregation anymore. It is in the simulation path itself, most likely from the still-active optimization:

- incremental maintenance of `theta_n2`

The current source still uses incremental `theta_n2` updates for:

- divergence checks
- max-theta bookkeeping
- projection-trigger decisions

That is enough to change:

- `final_theta_norm`
- `max_theta_norm`
- `ratio_max_over_theta_star_sq`
- `max_proj_clip_count`
- and in some cases, even final objectives, because projection/divergence timing can shift the trajectory itself

## Important semantic difference vs baseline

There is also a class of remaining `agg_case` differences where the fixed code is more defensible than the old baseline.

Example:

- `toyexample case0004 / inv_omega_t / none`

The baseline `agg_case` writes `inf` early, but the fixed code averages over the finite runs that are still valid at that checkpoint. This difference is caused by how mixed finite/nonfinite checkpoints are handled.

So not every remaining mismatch should be interpreted as a regression in the fixed code.

## Practical conclusion

### Answer to the request

If the acceptance criterion is:

- "Do the old `toyexample` and `E10` mismatches disappear as unexplained bugs?"

then the answer is:

- **mostly yes** for the two originally diagnosed pathologies

If the acceptance criterion is:

- "Does the current source now exactly reproduce the full old baseline matrix for `toyexample` and `E10`?"

then the answer is:

- **no**

### Most likely remaining cause

The remaining exactness gap is dominated by the incremental `theta_n2` optimization still present in [cpp/tdx.cpp](/home/leew0a/codex/TDfullexperiments/cpp/tdx.cpp).

To recover exact baseline agreement, the next targeted change should be:

- recompute `theta_n2 = w^T w` exactly at every step before divergence/projection checks

That would likely eliminate most of the remaining run-level mismatches, at some performance cost.

## Recommended next step

Do one more differential-debug round, but now only for the remaining unresolved class:

- `runs_case` mismatches driven by `final_theta_norm / max_theta_norm / max_proj_clip_count`

Specifically, compare a build with:

- exact per-step norm recomputation

against the current fixed source, first on:

- `toyexample`
- `E10`
- schedules with remaining mismatches: `inv_t`, `inv_sqrt_t`, `inv_t_2_3`, `constant`, `constant_omega`
