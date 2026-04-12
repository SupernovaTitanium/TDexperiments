# Large-Scale Benchmark Across All 11 TD Environment Families (2026-04-11)

## Goal

Evaluate whether the current local C++ engine already includes the full round-2 optimization set, and then measure its runtime on a larger workload against the stable GitHub baseline.

## Current code state

The current source in `cpp/tdx.cpp` **does include** the round-2 code changes.
Confirmed features present in source:

- `AlphaRuntime`
- compile-time `alpha_t_compiled<...>` schedule specialization
- `run_single_simulation_impl<Schedule, Projection>`
- `select_run_simulation_fn(...)`
- sparse transition support in the simulation path
- checkpoint-only objective computation
- incremental `||theta_t||^2` maintenance

Therefore, no extra round-2 patch application was needed before benchmarking.

## Benchmark definition

Two binaries were benchmarked:

- `baseline`: compiled from `git show HEAD:cpp/tdx.cpp` into `/tmp/tdx_bench_suite_20260411/tdx_baseline_d9c4dde`
- `round2`: copied from the current local build into `/tmp/tdx_bench_suite_20260411/tdx_round2_current`

Workload per environment family:

```bash
OMP_PLACES=cores OMP_PROC_BIND=spread <binary> sweep \
  --env <toyexample|E1|...|E10> \
  --base_values 1e-2 \
  --schedules theory,theory_log2,constant_omega,constant,inv_t,inv_sqrt_t,inv_t_2_3,inv_omega_t \
  --projections none,oracle,upper \
  --n_steps 1000000 \
  --n_runs 40 \
  --threads 40 \
  --outdir <tmpdir>
```

Important detail:

- Each environment family used its default sweep, which produced **4 cases**.
- So each environment family contributes `4 cases x 8 schedules x 3 projections = 96 experiment rows`.
- Across all 11 environment families, each binary ran **1056 experiment rows**.
- Across both binaries together, this benchmark executed **2112 experiment rows**.

## Timing results

| Env | Baseline (s) | Round 2 (s) | Speedup |
| --- | ---: | ---: | ---: |
| toyexample | 14.449061632 | 6.074874624 | 2.378x |
| E1 | 9.426679040 | 4.852056576 | 1.943x |
| E2 | 11.305753344 | 5.102839808 | 2.216x |
| E3 | 9.892035840 | 5.134114048 | 1.927x |
| E4 | 42.209291520 | 7.407786240 | 5.698x |
| E5 | 39.403849984 | 6.925476608 | 5.690x |
| E6 | 13.094291968 | 5.312172800 | 2.465x |
| E7 | 11.688499456 | 5.316848128 | 2.198x |
| E8 | 11.569726720 | 5.352015616 | 2.162x |
| E9 | 12.567654400 | 6.292465664 | 1.997x |
| E10 | 13.749957120 | 7.637251328 | 1.800x |

Total:

- Baseline total: `189.356801024 s`
- Round-2 total: `65.407901440 s`
- Overall speedup: **`2.895x`**

## Correctness comparison

I compared baseline vs round2 outputs environment-by-environment.

### Exact-match environments

These environment families were **byte-for-byte exact** across all generated files:

- `E1`
- `E2`
- `E3`
- `E4`
- `E5`
- `E6`
- `E7`
- `E8`
- `E9`

For these 9 environment families:

- file lists matched,
- `manifest.tsv` matched,
- all `agg_*.csv` matched exactly,
- all `runs_*.csv` matched exactly.

### Non-exact environments

Two environment families were **not** exact:

- `toyexample`
- `E10`

The mismatch is not limited to low-level floating-point noise.
There are files with large differences, especially in some `inv_omega_t` and projection-related runs.

Summary of worst observed differences:

- `toyexample`
  - differing CSV files: `129`
  - worst absolute difference: `1,860,225.54463`
  - worst example:
    - file: `agg_case_0002__sched_inv_omega_t__proj_upper__c_1.000e-02.csv`
    - row/col: `(2, 9)`
    - baseline: `1860225.54463`
    - round2: `0`

- `E10`
  - differing CSV files: `153`
  - worst absolute difference: `1.01519683032e+16`
  - worst example:
    - file: `agg_case_0003__sched_inv_omega_t__proj_none__c_1.000e-02.csv`
    - row/col: `(4, 7)`
    - baseline: `0`
    - round2: `1.01519683032e+16`

Additional notes:

- For both `toyexample` and `E10`, `manifest.tsv` still matched exactly.
- This indicates the mismatch is in numerical results, not in experiment enumeration or file naming.

## Interpretation

### What this benchmark verifies

- The current local source does contain the round-2 optimization code.
- On a much larger workload than the previous smoke tests, round2 is clearly faster than the stable baseline.
- The total speedup over this benchmark is about **2.90x**.
- On some environment families (`E4`, `E5`), the gain is about **5.7x**.

### What this benchmark does not verify

- It does **not** justify saying round2 is globally correctness-preserving yet.
- The benchmark exposed a real residual mismatch on `toyexample` and `E10`.
- Since those mismatches can be large, they should not be dismissed as harmless floating-point roundoff.

## Practical conclusion

For performance alone, round2 is already a substantial improvement.

For correctness, the current status is mixed:

- `9 / 11` environment families: exact-match
- `2 / 11` environment families: non-exact, with some large deviations

So the correct current statement is:

- **round2 is large-scale faster**, but
- **round2 is not yet fully validated across all 11 environment families**.

## Raw artifact locations

- Benchmark root: `/tmp/tdx_bench_suite_20260411`
- Timing table: `/tmp/tdx_bench_suite_20260411/large_benchmark_times.tsv`
- Benchmark log: `/tmp/tdx_bench_suite_20260411/large_benchmark.log`
- Baseline binary: `/tmp/tdx_bench_suite_20260411/tdx_baseline_d9c4dde`
- Round-2 binary: `/tmp/tdx_bench_suite_20260411/tdx_round2_current`

## Recommended next step

The next technically correct step is **not** another performance round.
The next step should be to isolate why `toyexample` and `E10` fail exact-match under the larger benchmark, most likely by checking the interaction among:

1. sparse transition sampling,
2. incremental norm tracking,
3. projection / clipping behavior,
4. dense-transition environments or the specific structures in `toyexample` and `E10`.
