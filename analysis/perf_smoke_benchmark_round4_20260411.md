# Round-4 High-Thread Optimization Experiment (2026-04-11)

## Scope

- Goal: optimize for the real workload regime `36-40` OpenMP threads, not for low-thread toy benchmarks.
- Reference binary: round-2 optimized binary saved as `/tmp/tdx_round2_round4base_20260411`.
- Candidate binary: a round-4 variant that combined thread-local checkpoint aggregation, OpenMP `proc_bind(spread)`, and `-flto`.
- Decision criterion: keep round 4 only if it improves or at least robustly matches round 2 in the target high-thread regime.

## Round-4 ideas tested

1. Replace run-level checkpoint trace storage plus serial aggregation with thread-local checkpoint accumulators.
2. Use an OpenMP parallel region with `schedule(static)` and `proc_bind(spread)` to better match the 36-40 thread regime.
3. Build with `-flto`.

## Correctness

### All-method smoke at 40 threads

Workload:

```bash
/tmp/tdx_round2_round4base_20260411 sweep --env E5 --sweep feature_omega_beta=1.0 --base_values 1e-2 --schedules theory,theory_log2,constant_omega,constant,inv_t,inv_sqrt_t,inv_t_2_3,inv_omega_t --projections none,oracle,upper --n_steps 50000 --n_runs 40 --threads 40 --outdir /tmp/tdx_round2_round4_smoke_20260411
./cpp/tdx sweep --env E5 --sweep feature_omega_beta=1.0 --base_values 1e-2 --schedules theory,theory_log2,constant_omega,constant,inv_t,inv_sqrt_t,inv_t_2_3,inv_omega_t --projections none,oracle,upper --n_steps 50000 --n_runs 40 --threads 40 --outdir /tmp/tdx_round4_smoke_20260411
```

Result:

- Compared `manifest.tsv`, all `agg_*.csv`, and all `runs_*.csv` with `cmp`.
- Status: **EXACT_MATCH** across all 24 method variants.

### Benchmark-output equality

For all benchmark workloads below, round2 vs round4 outputs were also **exact-match** file-by-file.

## High-thread benchmark

Benchmark workload:

```bash
OMP_PLACES=cores <binary> sweep --env E5 --sweep feature_omega_beta=1.0 --base_values 1e-2 --schedules <theory|inv_sqrt_t> --projections <none|upper> --n_steps 2000000 --n_runs 40 --threads <36|40> --outdir <tmpdir>
```

| Schedule | Projection | Threads | Round 2 (s) | Round 4 (s) | Speedup |
| --- | --- | ---: | ---: | ---: | ---: |
| theory | none | 36 | 0.232495360 | 0.220912384 | 1.052x |
| theory | none | 40 | 0.231342848 | 0.206351616 | 1.121x |
| theory | upper | 36 | 0.221389824 | 0.247765248 | 0.893x |
| theory | upper | 40 | 0.186586880 | 0.196791040 | 0.948x |
| inv_sqrt_t | none | 36 | 0.193708288 | 0.221289216 | 0.875x |
| inv_sqrt_t | none | 40 | 0.142898176 | 0.204195840 | 0.700x |
| inv_sqrt_t | upper | 36 | 0.185231104 | 0.230393856 | 0.804x |
| inv_sqrt_t | upper | 40 | 0.157926400 | 0.172840448 | 0.914x |

## Interpretation

Round 4 is numerically correct, but it does **not** improve the target regime robustly enough.

Observed behavior:

- `theory + none` improved at both `36` and `40` threads.
- Everything else in this benchmark matrix got worse, sometimes substantially.
- The worst regression here was `inv_sqrt_t + none + 40 threads`, where round 4 was only `0.700x` as fast as round 2.

The most likely reason is that thread-local checkpoint aggregation removes a serial post-pass, but the real hot path in these workloads is still the per-step simulation. In this setup, the extra accumulator writes and thread-local data structures do not consistently pay for themselves.

## Decision

Round 4 was **rejected**.

The source tree was restored to the round-2 implementation after benchmarking.
That restored source was checked again against the frozen round-2 binary and matched exactly.

## Raw artifacts

- Frozen round-2 binary: `/tmp/tdx_round2_round4base_20260411`
- Round-4 smoke roots:
  - `/tmp/tdx_round2_round4_smoke_20260411`
  - `/tmp/tdx_round4_smoke_20260411`
- Round-4 benchmark root: `/tmp/tdx_perf_round4_20260411`
- Restore-check roots:
  - `/tmp/tdx_round4_restore_20260411`
  - `/tmp/tdx_round4_restore_src_20260411`

## Recommended next direction

If we continue to a round 5, the next highest-value path is not more checkpoint aggregation work. The data here suggests focusing instead on:

1. a PGO-trained build for the exact high-thread workload,
2. reducing per-step arithmetic overhead further in the simulation loop,
3. exploring OpenMP affinity settings outside the code path first, before baking them into the source.
