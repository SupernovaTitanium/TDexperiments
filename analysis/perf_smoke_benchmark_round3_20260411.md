# Round-3 C++ Performance Experiment (2026-04-11)

## Scope

- Reference binary: round-2 optimized binary saved as `/tmp/tdx_round2_20260411`.
- Candidate binary: a round-3 variant that fused the unprojected `w` / `theta_bar` update pass and simplified checkpoint bookkeeping.
- Decision goal: determine whether round-3 should replace round-2 as the default experimental engine.

## Proposed round-3 changes

The tested round-3 variant made two additional hot-loop changes on top of round 2:

- For `projection=none`, fuse the `w` update loop and `theta_bar` update loop into a single pass.
- Replace repeated `checkpoints[cp_idx]` lookups by a cached `next_checkpoint` integer, and avoid one per-step `final_theta_norm` assignment.

These changes were designed to reduce vector passes in the no-projection path without changing semantics.

## Correctness checks

### All-method smoke

Workload:

```bash
/tmp/tdx_round2_20260411 sweep --env E5 --sweep feature_omega_beta=1.0 --base_values 1e-2 --schedules theory,theory_log2,constant_omega,constant,inv_t,inv_sqrt_t,inv_t_2_3,inv_omega_t --projections none,oracle,upper --n_steps 30000 --n_runs 6 --threads 4 --outdir /tmp/tdx_round2_dispatch_r3_20260411
./cpp/tdx sweep --env E5 --sweep feature_omega_beta=1.0 --base_values 1e-2 --schedules theory,theory_log2,constant_omega,constant,inv_t,inv_sqrt_t,inv_t_2_3,inv_omega_t --projections none,oracle,upper --n_steps 30000 --n_runs 6 --threads 4 --outdir /tmp/tdx_round3_dispatch_20260411
```

Result:

- Compared `manifest.tsv`, all `agg_*.csv`, and all `runs_*.csv` with `cmp`.
- Status: **EXACT_MATCH** across all 24 method variants.

### Benchmark-output equality

For the benchmark workloads below, round2 vs round3 outputs were also checked file-by-file and were **exact-match**.

## Benchmark A: same workload as round 2

Workload:

```bash
<binary> sweep --env E5 --sweep feature_omega_beta=1.0 --base_values 1e-2 --schedules theory --projections <none|upper> --n_steps 2000000 --n_runs 32 --threads <1|8|16|32> --outdir <tmpdir>
```

### Projection = none

| Threads | Round 2 (s) | Round 3 (s) | Speedup |
| --- | ---: | ---: | ---: |
| 1 | 2.009863936 | 1.828974848 | 1.099x |
| 8 | 0.349951232 | 0.348817408 | 1.003x |
| 16 | 0.223323648 | 0.219951360 | 1.015x |
| 32 | 0.134235648 | 0.142944000 | 0.939x |

### Projection = upper

| Threads | Round 2 (s) | Round 3 (s) | Speedup |
| --- | ---: | ---: | ---: |
| 1 | 1.829463808 | 1.804327680 | 1.014x |
| 8 | 0.355353088 | 0.360034560 | 0.987x |
| 16 | 0.250205952 | 0.212713728 | 1.176x |
| 32 | 0.160286976 | 0.155030528 | 1.034x |

## Benchmark B: extra schedule check on `projection=none`

Workload:

```bash
<binary> sweep --env E5 --sweep feature_omega_beta=1.0 --base_values 1e-2 --schedules <theory|inv_sqrt_t> --projections none --n_steps 2000000 --n_runs 32 --threads <1|16|32> --outdir <tmpdir>
```

### Schedule = theory

| Threads | Round 2 (s) | Round 3 (s) | Speedup |
| --- | ---: | ---: | ---: |
| 1 | 1.911956480 | 1.655001344 | 1.155x |
| 16 | 0.162263296 | 0.148588800 | 1.092x |
| 32 | 0.100512512 | 0.124967168 | 0.804x |

### Schedule = inv_sqrt_t

| Threads | Round 2 (s) | Round 3 (s) | Speedup |
| --- | ---: | ---: | ---: |
| 1 | 1.558631168 | 1.379218176 | 1.130x |
| 16 | 0.191871232 | 0.215414528 | 0.891x |
| 32 | 0.168435968 | 0.159066880 | 1.059x |

## Decision

Round 3 is **numerically correct but not robustly faster**.

Observed pattern:

- It helps in several low-thread or mid-thread settings.
- It does **not** dominate round 2 in higher-thread settings.
- The regressions are not catastrophic, but they matter because the main experiment workflow typically uses high thread counts.

Therefore, round 3 was **not adopted** as the new default implementation.
The source tree was restored to the round-2 implementation after benchmarking.

## Raw artifacts

- Round-2 frozen binary: `/tmp/tdx_round2_20260411`
- Round-3 benchmark root: `/tmp/tdx_perf_round3_20260411`
- Round-3 extra benchmark root: `/tmp/tdx_perf_round3_extra_20260411`
- Round-2 vs round-3 smoke roots:
  - `/tmp/tdx_round2_dispatch_r3_20260411`
  - `/tmp/tdx_round3_dispatch_20260411`
- Restore check roots:
  - `/tmp/tdx_round2_restorecheck_20260411`
  - `/tmp/tdx_round2_restorecheck_src_20260411`
