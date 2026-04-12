# Incremental norm gap summary (current-fixed vs exact-norm)

## Setup

Compared:

- current fixed source run directory
- exact-norm temporary binary run directory

on the same full benchmark matrices for:

- `toyexample`
- `E10`

with:

- `8` schedules
- `3` projections
- `4` cases per env
- `c = 1e-2`
- `n_steps = 1e6`
- `n_runs = 40`
- `threads = 40`

## Main result

The incremental norm update can be **small in many runs**, but it is **not uniformly negligible**.

Its largest effect is on:

- `final_theta_norm`
- `max_theta_norm`
- projection/clipping side effects
- derived aggregation using checkpoint theta norms

It is much less significant on final objectives.

## File-level impact

### toyexample

- `runs_case` differing files: `57 / 96`
- `agg_case` differing files: `62 / 96`

### E10

- `runs_case` differing files: `65 / 96`
- `agg_case` differing files: `72 / 96`

## Largest run-level differences

### toyexample

#### `final_theta_norm`

- max absolute difference: `3560`
- max relative difference: `0.9447`

Representative cases:

- `runs_case_0001__sched_inv_t__proj_none__c_1.000e-02.csv`
  - `6.50567295994e+12` vs `6.5056729635e+12`
  - absolute diff `3560`
  - relative diff `5.47e-10`
- `runs_case_0004__sched_inv_t_2_3__proj_none__c_1.000e-02.csv`
  - `3388.06557729` vs `187.242485448`
  - absolute diff `3200.823091842`
  - relative diff `0.9447`

So in hard nonprojected cases, the incremental norm update can change the reported final norm by **order-1 relative error**.

#### final objectives

- `final_obj_D` max abs diff: `5.3e-4`
- `final_obj_A` max abs diff: `1.23e-2`
- relative errors are tiny:
  - `final_obj_D` max rel diff: `4.20e-10`
  - `final_obj_A` max rel diff: `3.01e-10`

#### derived ratio

- `ratio_max_over_theta_star_sq` max abs diff: `1.0e-16`
- negligible

### E10

#### `final_theta_norm`

- max absolute difference: `0.6349265`
- max relative difference: `5.16e-5`

Representative case:

- `runs_case_0002__sched_inv_omega_t__proj_upper__c_1.000e-02.csv`
  - `12299.8665747` vs `12300.5015012`
  - abs diff `0.6349`
  - rel diff `5.16e-5`

So for E10, the direct norm drift is much smaller than toyexample.

#### `max_proj_clip_count`

- max absolute difference: `1895`
- max relative difference: `0.0173`

Representative case:

- `runs_case_0004__sched_constant__proj_oracle__c_1.000e-02.csv`
  - `109060` vs `110955`

So the incremental norm update can shift projection-trigger behavior by about `1.7%` in clip counts.

#### final objectives

- `final_obj_A` max abs diff: `1e-9`
- `final_obj_D` max abs diff: `1e-13`
- effectively negligible

## Largest aggregate-level differences

### toyexample

Most visible on checkpoint theta-norm aggregates.

- `E[||theta_t||^2]` max abs diff: `100000`
- worst relative diff: `0.9236`

Representative case:

- `agg_case_0004__sched_inv_t_2_3__proj_none__c_1.000e-02.csv`
  - `1426.22666357` vs `108.901023457`
  - relative diff `0.9236`

This is the clearest evidence that incremental norm maintenance can materially distort aggregate theta-norm statistics in hard nonprojected toyexample cases.

### E10

- `E[||theta_t||^2]` max abs diff: `1e6`
- but on a `4.26e17` scale in the worst absolute case
- the more meaningful issue is:
  - `std_max_theta` can move from `0` to `2.5298`
  - `std_D/std_A` differences can remain nontrivial in some projected `inv_omega_t` cases

Representative case:

- `agg_case_0001__sched_inv_omega_t__proj_upper__c_1.000e-02.csv`
  - `std_max_theta`: `0` vs `2.52982212813`

## Practical interpretation

### If you care about final objectives only

The incremental norm update is usually a **small effect**:

- toyexample: objective differences up to about `1e-2` absolute, tiny relative
- E10: objective differences essentially negligible

### If you care about norm-based diagnostics or projection behavior

The incremental norm update can be **material**:

- toyexample hard cases: final norm can change by about `94%` relative
- E10 projected cases: clip counts can shift by about `1.7%`
- aggregate theta-norm statistics can move a lot in difficult nonprojected toyexample cases

## Conclusion

A concise answer is:

- **for value/objective curves: usually small**
- **for theta-norm / projection / divergence-adjacent bookkeeping: sometimes large**
- the worst observed practical distortion in this benchmark slice was a toyexample hard case where final theta norm changed from about `3388` to `187`, i.e. about **94% relative difference**
