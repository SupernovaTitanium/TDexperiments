# RNG Alignment and C++/Julia Consistency Analysis (1e7 steps, 48 runs)

Date: 2026-04-02

## Goal

Determine whether C++ vs Julia gaps are due to randomness mismatch, floating-point roundoff, or implementation errors.

## Changes applied

1. Unified RNG algorithm in both implementations to SplitMix64:
- Julia: `TDThreshold.jl` (`SplitMix64RNG`, `rand_unit`, `stable_seed`)
- C++: `cpp/tdx.cpp` (`SplitMix64Rng`, same seed mixer)

2. Unified toyexample random matrix construction order:
- both now consume RNG in row-major visitation order for `r` and `Phi`.

3. Unified simulation randomness source:
- both TD step samplers now consume one `U(0,1)` from SplitMix64 per step.

4. Unified divergence aggregation semantics:
- Julia aggregation now skips non-finite checkpoints, matching C++ behavior.

5. Julia summary parallelization:
- `scripts/julia_theory_summary.jl` uses `Threads.@threads` over runs.

## Full run setup

- Environments: toyexample + E1..E12
- Scale grid: 17 values from 1e-5 to 1e3 (half-decade)
- Steps per run: 10,000,000
- Monte Carlo runs: 48
- Schedule/projection: theory + none

Artifacts:
- C++ root: `td_cxx_logs_full_1e7_rng`
- Julia summary: `verification/julia_theory_summary_1e7_48_rng.tsv`
- C++ summary: `verification/cpp_theory_summary_1e7_48_rng.tsv`
- Comparison: `verification/cpp_vs_julia_compare_1e7_48_rng.tsv`

## Quantitative results

Matched rows: 221 (13 environments x 17 scales)

Max errors:
- omega relative error: `2.17132004291e-12`
- kappa relative error: `1.59978905382e-12`
- final_D relative error: `1.61172440074e-10`
- final_A relative error: `2.22882396144e-10`
- divergence-rate absolute error: `0`

Absolute error scale:
- max |final_D_cpp - final_D_julia| = `5.599999512094197e-17`
- max |final_A_cpp - final_A_julia| = `1.240000330605777e-15`

Non-zero relative final-D/A errors only appear in 4 toyexample rows; all are at floating-point-noise scale.

## Before/after evidence (200k verification slice)

Before alignment (`verification/cpp_vs_julia_compare_48.tsv`):
- omega max rel: `2.8005e-02`
- kappa max rel: `5.4181e-02`
- final_D max rel: `6.0724e-01`
- final_A max rel: `7.4924e-01`
- div abs max: `1.0417e-01`

After alignment (`verification/cpp_vs_julia_compare_48_rng.tsv`):
- omega max rel: `2.1713e-12`
- kappa max rel: `1.5998e-12`
- final_D max rel: `0`
- final_A max rel: `0`
- div abs max: `0`

## Conclusion

The original discrepancy was caused by implementation mismatches (RNG stream + divergence aggregation semantics), not by the TD update logic itself.

After unification, remaining C++/Julia differences are at floating-point roundoff scale only, with identical divergence outcomes across all 221 full-scale points.
