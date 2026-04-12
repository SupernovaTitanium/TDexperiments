# Revalidation Gate: toyexample + E10 (2026-04-12)

## Goal

After removing incremental norm from production source, rerun the full benchmark matrix for:

- `toyexample`
- `E10`

and use this as a gate:

- if both families match the stable baseline exactly, then start the 44-case correctness revalidation
- otherwise, stop here

## Compared binaries

- baseline: `/tmp/tdx_bench_suite_20260411/tdx_baseline_d9c4dde`
- current: `/home/leew0a/codex/TDfullexperiments/cpp/tdx`

## Benchmark settings

- `base_values = 1e-2`
- `schedules = theory,theory_log2,constant_omega,constant,inv_t,inv_sqrt_t,inv_t_2_3,inv_omega_t`
- `projections = none,oracle,upper`
- `n_steps = 1e6`
- `n_runs = 40`
- `threads = 40`

Each environment family uses the default 4 cases, so each family produces:

- `96 runs_case_*.csv`
- `96 agg_case_*.csv`
- `1 manifest.tsv`

Total per family: `193 files`

## Output directories

- toyexample baseline:
  `/tmp/tdx_bench_toy_e10_exactcheck_20260412/out_baseline_toyexample/toyexample_20260412_010942`
- toyexample current:
  `/tmp/tdx_bench_toy_e10_exactcheck_20260412/out_current_toyexample/toyexample_20260412_010956`
- E10 baseline:
  `/tmp/tdx_bench_toy_e10_exactcheck_20260412/out_baseline_E10/E10_20260412_011003`
- E10 current:
  `/tmp/tdx_bench_toy_e10_exactcheck_20260412/out_current_E10/E10_20260412_011017`

## Gate result

The gate **does not pass**.

### toyexample

- total files: `193`
- differing files: `88`
- `manifest.tsv`: `0`
- `runs_case_*.csv`: `9`
- `agg_case_*.csv`: `79`

### E10

- total files: `193`
- differing files: `97`
- `manifest.tsv`: `0`
- `runs_case_*.csv`: `6`
- `agg_case_*.csv`: `91`

## Interpretation

This matches the earlier exact-norm differential-debug result:

- the dominant run-level mismatch from incremental `theta_n2` is now largely removed
- but exact full-matrix agreement with the old baseline is still not achieved

The remaining differences are therefore **not** explained by incremental norm anymore.

They are concentrated in:

- `agg_case_*.csv`
- a very small residual set of `runs_case_*.csv`

So the current production source is much closer to the baseline than the old round-2 incremental-norm build, but it is still not byte-for-byte exact on these two hardest families.

## Decision

Because the gate criterion was:

- exact baseline agreement on `toyexample + E10`

the next step is **not** to start the 44-case correctness revalidation.

The 44-case revalidation is therefore **not started**.

## Recommended next step

Investigate the remaining post-incremental-norm mismatch, which is now likely due to:

1. aggregation semantics versus the old baseline
2. residual tiny run-level floating-point path differences
3. possibly `-ffast-math` related exactness behavior

The next technically correct move is another targeted differential-debug pass on the remaining `9 + 6` run-level mismatches and a deliberate decision on whether the old aggregation semantics should be preserved or retired.
