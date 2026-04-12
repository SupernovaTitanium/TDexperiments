# Final Differential Debugging for Remaining `runs_case` Mismatches (2026-04-12)

## Goal

Isolate the final remaining `runs_case` mismatches after:

1. projection bookkeeping fix
2. aggregation stability fix
3. exact per-step norm recomputation

At this stage the remaining `runs_case` mismatches were:

- `toyexample`: `9`
- `E10`: `6`

and all of them were tiny `final_obj_D / final_obj_A` tails.

## First narrowing: what still differed

From the post-exact-norm full matrix:

### toyexample

Remaining differing files:

- `runs_case_0002__sched_inv_omega_t__proj_upper__c_1.000e-02.csv`
- `runs_case_0003__sched_inv_omega_t__proj_upper__c_1.000e-02.csv`
- `runs_case_0004__sched_inv_omega_t__proj_upper__c_1.000e-02.csv`
- `runs_case_0004__sched_theory__proj_none__c_1.000e-02.csv`
- `runs_case_0004__sched_theory__proj_oracle__c_1.000e-02.csv`
- `runs_case_0004__sched_theory__proj_upper__c_1.000e-02.csv`
- `runs_case_0004__sched_theory_log2__proj_none__c_1.000e-02.csv`
- `runs_case_0004__sched_theory_log2__proj_oracle__c_1.000e-02.csv`
- `runs_case_0004__sched_theory_log2__proj_upper__c_1.000e-02.csv`

### E10

Remaining differing files:

- `runs_case_0004__sched_theory__proj_none__c_1.000e-02.csv`
- `runs_case_0004__sched_theory__proj_oracle__c_1.000e-02.csv`
- `runs_case_0004__sched_theory__proj_upper__c_1.000e-02.csv`
- `runs_case_0004__sched_theory_log2__proj_none__c_1.000e-02.csv`
- `runs_case_0004__sched_theory_log2__proj_oracle__c_1.000e-02.csv`
- `runs_case_0004__sched_theory_log2__proj_upper__c_1.000e-02.csv`

## Column-level diagnosis

For all 15 files, the differing columns were only:

- `final_obj_D`
- `final_obj_A`

No remaining differences were observed in:

- `diverged`
- `diverged_at`
- `final_theta_norm`
- `max_theta_norm`
- `ratio_max_over_theta_star_sq`
- `max_alpha`
- `max_proj_clip_count`

So the remaining issue was no longer:

- randomness / RNG
- transition sampling
- projection timing
- divergence timing
- norm bookkeeping

## Hypothesis tests

### Hypothesis 1: objective-computation path caused the tail differences

Temporary binary:

- `/tmp/tdx_everyobj`

Change:

- restored old-style inline per-step objective computation

Result:

- the 15 `runs_case` mismatches remained

Conclusion:

- the final tails were **not** caused by the refactored objective-evaluation path

### Hypothesis 2: `alpha_t_compiled<S>` schedule specialization caused the tail differences

Temporary binary:

- `/tmp/tdx_runtimealpha`

Change:

- replaced

```cpp
const double alpha = alpha_t_compiled<S>(alpha_rt, t);
```

with

```cpp
const double alpha = alpha_t(spec, env, metrics, t, n_steps, t0);
```

keeping the exact-norm fix.

Representative checks:

- `toyexample case0004 / theory / none`: exact
- `E10 case0004 / theory / none`: exact
- `toyexample case0002 / inv_omega_t / upper`: exact

Then all 15 remaining mismatch files were rerun under the runtime-alpha variant.

Result:

- all 15 became exact matches against the baseline outputs

## Conclusion

The final remaining `runs_case` mismatches were caused by:

- **`alpha_t_compiled<S>` schedule specialization**

not by the objective computation path.

Most likely mechanism:

- under `-ffast-math` and the refactored template-specialized loop, the specialized stepsize path produces tiny floating differences relative to the old baseline runtime path
- these differences are too small to affect divergence / norm / clipping diagnostics
- but they are large enough to change the printed `final_obj_D / final_obj_A` in the last few digits

## Production fix applied

The production source was updated from:

```cpp
const AlphaRuntime alpha_rt = make_alpha_runtime(spec, env, metrics, n_steps, t0);
...
const double alpha = alpha_t_compiled<S>(alpha_rt, t);
```

to:

```cpp
const double alpha = alpha_t(spec, env, metrics, t, n_steps, t0);
```

in:

- [cpp/tdx.cpp](/home/leew0a/codex/TDfullexperiments/cpp/tdx.cpp)

## After applying the production fix

Full matrix rerun on `toyexample + E10`:

### toyexample

- total files: `193`
- differing files: `72`
- `manifest.tsv`: `0`
- `runs_case_*.csv`: `0`
- `agg_case_*.csv`: `72`

### E10

- total files: `193`
- differing files: `91`
- `manifest.tsv`: `0`
- `runs_case_*.csv`: `0`
- `agg_case_*.csv`: `91`

So:

- **all remaining `runs_case` mismatches are resolved**
- `agg_case` differences still remain, but they are a separate aggregation-semantics issue

## Practical consequence

If the target is:

- exact run-level agreement with the baseline

then this debugging round succeeds.

If the target is:

- full file-by-file exactness including `agg_case_*.csv`

then one unresolved class still remains:

- aggregation semantics versus the old baseline
