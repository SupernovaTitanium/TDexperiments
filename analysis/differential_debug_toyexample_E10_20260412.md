# Differential Debugging: toyexample and E10 (2026-04-12)

## Scope

This note isolates the correctness mismatches reported in the large benchmark between:

- baseline binary: `/tmp/tdx_bench_suite_20260411/tdx_baseline_d9c4dde`
- current optimized source: [cpp/tdx.cpp](/home/leew0a/codex/TDfullexperiments/cpp/tdx.cpp)

The original large benchmark reported exact matches on `E1`-`E9`, and only `toyexample` / `E10` showed mismatching `agg_case_*.csv` files.

## Initial symptom

From `/tmp/tdx_bench_suite_20260411`:

- `toyexample` worst mismatch:
  - `agg_case_0002__sched_inv_omega_t__proj_upper__c_1.000e-02.csv`
  - baseline `std_max_theta = 1860225.54463`
  - round2 `std_max_theta = 0`
- `E10` worst mismatch:
  - `agg_case_0003__sched_inv_omega_t__proj_none__c_1.000e-02.csv`
  - baseline `std_D = 0`, `std_A = 1.03498390482e+16`
  - round2 `std_D = 1.01519683032e+16`, `std_A = 7.64469654557e+15`

A key early observation was:

- `runs_case_*.csv` could be exactly equal while `agg_case_*.csv` differed.

So the bug was unlikely to be in final run summaries; it had to be in checkpoint logging / aggregation.

## Minimal reproductions used

### toyexample, problematic case

- env: `toyexample`
- case: `feature_omega_beta=1e-2`
- schedule: `inv_omega_t`
- projection: `upper`
- `c=1e-2`, `n_steps=1e6`, `n_runs=40`, `threads=1`

### E10, problematic case

- env: `E10`
- case: `eps2=1e-1`
- schedule: `inv_omega_t`
- projection: `none`
- `c=1e-2`, `n_steps=1e6`, `n_runs=40`, `threads=1`

## What was ruled out

### Not an OpenMP race

The mismatches reproduce with `threads=1`.

### Not a run-summary bug

For the two key problematic files, the corresponding `runs_case_*.csv` were exactly equal between baseline and optimized versions.

### Not the sparse sampler

A dense-sampler rollback variant was built and tested for `E10`; the `E10` mismatch persisted unchanged. So the sparse transition sampler is not the cause of the `E10` discrepancy.

## Root cause 1: projection bookkeeping bug in toyexample

### Finding

In the optimized code, after projection clipping we had:

```cpp
theta_n2 = proj_R2;
```

This forced every clipped iterate to have exactly the same recorded squared norm, even though after floating-point scaling the actual squared norm is only approximately `proj_R2`.

### Why it matters

For `toyexample + inv_omega_t + upper`, clipping happens immediately and repeatedly. Setting `theta_n2` exactly to `proj_R2` artificially collapses the checkpoint dispersion in `theta_norms`, so `std_max_theta` was driven to zero.

### Fix

Recompute the norm from the post-projection vector:

```cpp
theta_n2 = std::inner_product(w.begin(), w.end(), w.begin(), 0.0);
```

### Verification

After applying this change, the toyexample problematic case no longer had the structural `std_max_theta = 0` artifact.

## Root cause 2: unstable variance computation in aggregation

### Old code

The old aggregation used:

```cpp
std = sqrt(E[x^2] - E[x]^2)
```

implemented as:

```cpp
sv += v;
sv2 += v * v;
av = sv / cnt;
std = sqrt(max(0, sv2 / cnt - av * av));
```

### Why this is wrong here

For checkpoint values on the order of:

- `1e13` to `1e14` in clipped toyexample runs
- `1e23` in `E10` explosive unprojected runs

this formula suffers catastrophic cancellation. Even when all runs are effectively identical, floating roundoff in `sv2 / cnt - av^2` can produce huge fake standard deviations.

### Direct evidence from E10

Instrumented per-run checkpoint traces for the problematic `E10` case showed:

- all 40 runs had the same checkpoint values up to the printed precision
- baseline and optimized traces differed only in last-bit floating tails

Example, `run=1`, `t=2`:

- baseline: `theta=2.5999648030224933e+19`
- optimized: `theta=2.5999648030224937e+19`

Example, `run=1`, `t=3`:

- baseline: `D=3.2063416652547082e+23`
- optimized: `D=3.2063416652547069e+23`

These are tiny relative perturbations, but the unstable `E[x^2]-E[x]^2` formula magnifies them into fake `1e16`-scale `std_D/std_A` values.

### Fix

Replace the variance computation with Welford's online algorithm.

That is now implemented via `RunningStat` in [cpp/tdx.cpp](/home/leew0a/codex/TDfullexperiments/cpp/tdx.cpp).

### Result

For the problematic `E10` case after the fix:

- `std_D = 0`
- `std_A = 0`
- `std_max_theta = 0`

which matches the traced fact that the checkpoint values are effectively identical across runs.

## Root cause 3: `-ffast-math` broke the intended finite-value filtering in aggregation

### Intended semantics

The original code tried to skip non-finite checkpoint values:

```cpp
if (!std::isfinite(v) || !std::isfinite(va) || !std::isfinite(th)) continue;
```

### What actually happened

Under `-ffast-math`, this was not reliable enough in the hot aggregation path.

This explains two benchmark pathologies:

1. `E10`: rows with all-`inf` trajectories could contaminate the variance computation.
2. `toyexample case0004 / inv_omega_t / none`: baseline row 3 became `inf`, while the fixed version produced a large but finite mean over the still-finite subset of runs.

### Why toyexample case0004 row 3 differs

For `toyexample case0004 / inv_omega_t / none / c=1e-2`, the exact `runs_case_*.csv` match between baseline and fixed current version.

The run-level divergence times are:

- `diverged_at = 2`: 25 runs
- `diverged_at = 3`: 15 runs

At checkpoint `t=3`:

- runs diverged at `t=2` contribute `inf`
- runs diverged at `t=3` still have a finite checkpoint-3 value, because the code records checkpoint values before the divergence break is triggered

So the intended aggregated mean at row 3 is the mean over the 15 finite trajectories, not `inf`.

The baseline `inf` row is therefore an artifact of non-finite handling under the old aggregation path.

### Fix

A strict bit-level finite check was added:

```cpp
static inline bool is_finite_strict(const double x)
```

This avoids relying on `std::isfinite` in a `-ffast-math` build.

Additionally, when a checkpoint has no finite values across runs, the fixed code now explicitly writes:

- average columns = `inf`
- standard deviation columns = `0`

This preserves sane post-divergence output.

## Code changes applied

The current source [cpp/tdx.cpp](/home/leew0a/codex/TDfullexperiments/cpp/tdx.cpp) now includes three correctness fixes:

1. projection clipping recomputes `theta_n2` from the clipped vector
2. checkpoint standard deviations use Welford accumulation
3. aggregation uses `is_finite_strict()` and explicit all-nonfinite handling

## Verification summary

### Verified

- `E10`, `n_runs=1`, problematic case:
  - baseline vs fixed current `agg_case_*.csv`: exact match
- `toyexample`, `n_runs=1`, problematic upper-projection case:
  - baseline vs fixed current `agg_case_*.csv`: only tiny floating-tail differences remain
  - worst observed difference: about `1e-5` in `E_D`
- `toyexample case0004 / inv_omega_t / none`, `n_runs=40`:
  - `runs_case_*.csv` are exact between baseline and fixed current
  - row-3 `agg_case_*.csv` difference is explained by finite-run filtering semantics, not by trajectory mismatch
- `E10 case0003 / inv_omega_t / none`, `n_runs=40`:
  - per-run checkpoint traces show the dynamics match up to last-bit tails
  - the old huge `std_*` values are aggregation artifacts, not simulation divergence

### Not re-run yet

I did **not** re-run the full 44-case large benchmark after the fix.

So the remaining statement is:

- for `toyexample` and `E10`, the previously reported mismatches are now explained and locally fixed
- but I have not yet regenerated the full benchmark matrix with the corrected source

## Practical conclusion

The large-benchmark mismatch report mixed together two different classes of issues:

1. **real bookkeeping bug**
   - projection path recorded `theta_n2` incorrectly after clipping
2. **aggregation/reporting numerical artifacts**
   - unstable variance formula
   - unreliable non-finite filtering under `-ffast-math`

After the current fixes, the remaining differences from the old baseline outputs are mostly because the old baseline `agg_case_*.csv` themselves were numerically misleading in `std_*` and mixed finite/nonfinite checkpoints.
