# Final Exact Revalidation (2026-04-12)

## Goal

Restore full baseline exactness while preserving as much of the useful round-2 speedup structure as possible.

The immediate target sequence was:

1. fix remaining `runs_case` mismatches on `toyexample + E10`
2. fix remaining `agg_case` mismatches on `toyexample + E10`
3. if both pass, run full 44-case correctness revalidation

## Final production decisions

The following optimizations were **not kept** because baseline exactness had higher priority:

1. incremental `theta_n2` maintenance
2. specialized `alpha_t_compiled<S>` stepsize evaluation
3. new aggregation semantics based on Welford + strict finite filtering

The following improvements remain in the production source:

1. sparse transition support
2. schedule/projection dispatch through `run_single_simulation_impl<Schedule, Projection>`
3. checkpoint-only objective logging structure

## Production source status

File:

- [cpp/tdx.cpp](/home/leew0a/codex/TDfullexperiments/cpp/tdx.cpp)

Baseline-exactness-restoring changes now present in production:

### 1. exact per-step norm recomputation

Production now uses:

```cpp
theta_n2 = std::inner_product(w.begin(), w.end(), w.begin(), 0.0);
```

instead of incremental norm updates.

### 2. runtime stepsize evaluation

Production now uses:

```cpp
const double alpha = alpha_t(spec, env, metrics, t, n_steps, t0);
```

instead of:

```cpp
const double alpha = alpha_t_compiled<S>(alpha_rt, t);
```

### 3. baseline aggregation semantics

Production `aggregate_results(...)` now matches the old baseline behavior:

- skip nonfinite checkpoint values using `std::isfinite`
- use `denom = max(1, cnt)`
- compute variance by `E[x^2] - E[x]^2`
- when `cnt = 0`, output zeros rather than the newer `inf`-fill convention

## Validation sequence

### Phase A: `toyexample + E10` gate after run-level fixes

After removing incremental norm and reverting to runtime `alpha_t(...)`, the remaining `runs_case` mismatches disappeared.

But `agg_case` mismatches still remained.

### Phase B: `toyexample + E10` gate after aggregation rollback

Current outputs:

- toyexample current:
  `/tmp/tdx_gate_after_aggfix_20260412/out_current_toyexample/toyexample_20260412_163804`
- E10 current:
  `/tmp/tdx_gate_after_aggfix_20260412/out_current_E10/E10_20260412_163808`

Baseline outputs:

- toyexample baseline:
  `/tmp/tdx_bench_toy_e10_exactcheck_20260412/out_baseline_toyexample/toyexample_20260412_010942`
- E10 baseline:
  `/tmp/tdx_bench_toy_e10_exactcheck_20260412/out_baseline_E10/E10_20260412_011003`

Gate result:

- `toyexample`: `193 / 193` files exact
- `E10`: `193 / 193` files exact

So the two hardest families fully passed.

## Full 44-case correctness revalidation

### Current outputs used

- `toyexample`, `E10`:
  `/tmp/tdx_gate_after_aggfix_20260412/out_current_*`
- `E1` to `E9`:
  `/tmp/tdx_revalidate_all11_20260412/out_current_*`

### Baseline outputs used

From:

- `/tmp/tdx_bench_suite_20260411/out_baseline_*`

### Workload definition

For each environment family:

- default 4 cases
- `base_values = 1e-2`
- `schedules = theory,theory_log2,constant_omega,constant,inv_t,inv_sqrt_t,inv_t_2_3,inv_omega_t`
- `projections = none,oracle,upper`
- `n_steps = 1e6`
- `n_runs = 40`
- `threads = 40`

Total per family:

- `96 runs_case_*.csv`
- `96 agg_case_*.csv`
- `1 manifest.tsv`

Total across all 11 families:

- `2123 files`

## Final exact-compare result

| Env | Total files | Diff files | Manifest | Runs | Agg |
| --- | ---: | ---: | ---: | ---: | ---: |
| toyexample | 193 | 0 | 0 | 0 | 0 |
| E1 | 193 | 0 | 0 | 0 | 0 |
| E2 | 193 | 0 | 0 | 0 | 0 |
| E3 | 193 | 0 | 0 | 0 | 0 |
| E4 | 193 | 0 | 0 | 0 | 0 |
| E5 | 193 | 0 | 0 | 0 | 0 |
| E6 | 193 | 0 | 0 | 0 | 0 |
| E7 | 193 | 0 | 0 | 0 | 0 |
| E8 | 193 | 0 | 0 | 0 | 0 |
| E9 | 193 | 0 | 0 | 0 | 0 |
| E10 | 193 | 0 | 0 | 0 | 0 |

Global result:

- **all 11 environment families are now exact matches**
- **all 44 cases are correctness-revalidated**
- **all `manifest.tsv`, `runs_case_*.csv`, and `agg_case_*.csv` match baseline byte-for-byte**

## Practical conclusion

Baseline exactness is restored.

The technically safe statement is now:

- the current production source reproduces the stable baseline exactly on the full 44-case benchmark workload

## Artifact locations

- gate outputs:
  - `/tmp/tdx_gate_after_aggfix_20260412`
- full current revalidation outputs:
  - `/tmp/tdx_revalidate_all11_20260412`
- baseline reference outputs:
  - `/tmp/tdx_bench_suite_20260411`
