# Incremental Norm Removal (2026-04-12)

## Decision

User priority is baseline exactness, so the incremental `theta_n2` optimization is removed from production source.

## Source change

File: `cpp/tdx.cpp`

Changed from:

```cpp
theta_n2 += 2.0 * beta * dot_phi + beta * beta * env.phi_row_sq[static_cast<size_t>(s)];
```

to:

```cpp
theta_n2 = std::inner_product(w.begin(), w.end(), w.begin(), 0.0);
```

## Why

Earlier differential debugging showed that incremental norm maintenance was the dominant remaining source of run-level mismatch versus the baseline binary.

## Minimal recheck after applying the change

### Toyexample sensitive reproducer

Command:

```bash
./cpp/tdx sweep --env toyexample --set feature_omega_beta=1e-2 --base_values 1e-2 --schedules inv_omega_t --projections upper --n_steps 1000000 --n_runs 40 --threads 40 --outdir /tmp/recheck_exactnorm_toy
```

Comparison target:

`/tmp/ddbg_toy_b1/toyexample_20260412_000534/runs_case_0001__sched_inv_omega_t__proj_upper__c_1.000e-02.csv`

Result:

- All rows match except one tiny final-objective rounding tail:
  - row 37 `final_obj_A`
  - `309.003561669` vs `309.003561668`

### E10 sensitive reproducer

Command:

```bash
./cpp/tdx sweep --env E10 --set eps2=1e-1 --base_values 1e-2 --schedules inv_omega_t --projections none --n_steps 1000000 --n_runs 40 --threads 40 --outdir /tmp/recheck_exactnorm_e10
```

Comparison target:

`/tmp/ddbg_e10_b1/E10_20260412_000534/runs_case_0001__sched_inv_omega_t__proj_none__c_1.000e-02.csv`

Result:

- Exact match on the run-level CSV.

## Current status

- Production source now uses exact per-step norm recomputation.
- Other round2 optimizations remain in place.
- Full 44-case correctness revalidation has not yet been rerun after this source change.
