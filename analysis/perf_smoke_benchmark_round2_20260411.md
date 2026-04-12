# Round-2 C++ Performance Benchmark (2026-04-11)

## Scope

- Baseline for this comparison: first optimized binary from round 1, saved as `/tmp/tdx_round1_20260411`.
- Candidate: current `cpp/tdx` after round-2 optimization.
- Stable GitHub baseline was already pushed earlier as commit `d9c4dde`.

## Round-2 code changes

- Specialized the hottest simulation loop by `(schedule, projection)` using compile-time dispatch.
- Moved schedule-dependent branch selection out of the per-step loop.
- Precomputed alpha-schedule constants (`c`, `phi_max_sq`, `omega`, `log(n_steps)`, `t0`) once per run via `AlphaRuntime`.
- Kept output formats and formulas unchanged.

## Correctness smoke: all schedules and projections

Workload:

```bash
/tmp/tdx_round1_20260411 sweep --env E5 --sweep feature_omega_beta=1.0 --base_values 1e-2 --schedules theory,theory_log2,constant_omega,constant,inv_t,inv_sqrt_t,inv_t_2_3,inv_omega_t --projections none,oracle,upper --n_steps 30000 --n_runs 6 --threads 4 --outdir /tmp/tdx_round1_dispatch_20260411
./cpp/tdx sweep --env E5 --sweep feature_omega_beta=1.0 --base_values 1e-2 --schedules theory,theory_log2,constant_omega,constant,inv_t,inv_sqrt_t,inv_t_2_3,inv_omega_t --projections none,oracle,upper --n_steps 30000 --n_runs 6 --threads 4 --outdir /tmp/tdx_round2_dispatch_20260411
```

Result:

- Compared `manifest.tsv`, all `agg_*.csv`, and all `runs_*.csv` with `cmp`.
- Status: **EXACT_MATCH** across all 24 method variants (8 schedules x 3 projections).

## Performance benchmark

Benchmark workload:

```bash
<binary> sweep --env E5 --sweep feature_omega_beta=1.0 --base_values 1e-2 --schedules theory --projections <none|upper> --n_steps 2000000 --n_runs 32 --threads <1|8|16|32> --outdir <tmpdir>
```

### Projection = none

| Threads | Round 1 (s) | Round 2 (s) | Speedup |
| --- | ---: | ---: | ---: |
| 1 | 2.306571776 | 1.895294464 | 1.217x |
| 8 | 0.389261568 | 0.336465664 | 1.157x |
| 16 | 0.251810304 | 0.201179904 | 1.252x |
| 32 | 0.156433152 | 0.130889216 | 1.195x |

### Projection = upper

| Threads | Round 1 (s) | Round 2 (s) | Speedup |
| --- | ---: | ---: | ---: |
| 1 | 2.247366400 | 1.930307840 | 1.164x |
| 8 | 0.496217600 | 0.330887680 | 1.500x |
| 16 | 0.268714752 | 0.237978112 | 1.129x |
| 32 | 0.211674880 | 0.176008192 | 1.203x |

## Output comparison on benchmark workload

- Compared round1 vs round2 benchmark outputs for every `(projection, threads)` pair.
- Pairs checked: `(none,1)`, `(none,8)`, `(none,16)`, `(none,32)`, `(upper,1)`, `(upper,8)`, `(upper,16)`, `(upper,32)`.
- Result: **all files exact-match** (`manifest.tsv`, `agg_*.csv`, `runs_*.csv`).

## Raw artifact locations

- Round-1 frozen binary: `/tmp/tdx_round1_20260411`
- Round-2 benchmark root: `/tmp/tdx_perf_round2_20260411`
- Round-1 correctness smoke root: `/tmp/tdx_round1_dispatch_20260411`
- Round-2 correctness smoke root: `/tmp/tdx_round2_dispatch_20260411`

## Takeaway

- Round 2 preserves outputs exactly on both the all-method smoke check and the longer benchmark workload.
- Round 2 gives an additional end-to-end speedup over round 1 of about `1.13x` to `1.50x`, depending on thread count and whether projection is active.
- The largest observed gain in this benchmark was `1.500x` for `projection=upper`, `threads=8`.
