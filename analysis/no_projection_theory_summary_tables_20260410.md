# No-Projection Theory TD: Summary Tables (2026-04-10)

## Scope
- Data root: `/home/leew0a/codex/TDfullexperiments/td_cxx_logs_full_1e8_n40_44instances_c15_1em7_1e7`
- Total experiment grid: `44 cases × 8 schedules × 3 projections × 15 c values`
- Horizon: `n_steps = 1e8`
- Monte Carlo runs per configuration: `40`
- Main objective: `D := E_D[||Vbar_t - V*||^2]`
- Secondary objective: `D+A := E_D[||Vbar_t - V*||^2] + E_A[||Vbar_t - V*||^2]`
- Stability definition: a configuration is called **stable** if all 40 runs satisfy `diverged = 0`

## Executive Table

| Question | Short answer | Evidence strength | Safe conclusion |
|---|---|---|---|
| Does `no projection + theory` dominate all methods? | No | strong | Not supported |
| Does `no projection + theory` have any real advantage? | Yes | strong | Strong unprojected robust baseline |
| Where is the clearest advantage? | Aggressive small-`c` stability | strong | Better than most classical unprojected schedules |
| Does data support early `t^{-1/2}`, late `1/(omega t)`? | Partially yes | medium | Supported in aggregate, not uniformly case-by-case |
| Which schedule shows the cleanest two-phase evidence? | `theory_log2 + none` | medium | Best aggregate slope match |
| Does convergence depend on `omega`? | Yes, strongly | strong | Dependence grows over time and is near `1/omega` by `T=1e8` |
| Do hardest small-`omega` cases reach the fast phase by `1e8`? | Usually not | strong | Fast phase is delayed when `omega` is small |

## Claim / Evidence / Verdict Table

| Claim | Evidence | Verdict |
|---|---|---|
| `theory + none` is the best overall method | Best-stable global tie only `12/44` on `D`, `11/44` on `D+A` | Not supported |
| `theory_log2 + none` is the best overall method | Best-stable global tie only `13/44` on `D`, `6/44` on `D+A` | Not supported |
| `theory + none` is a strong unprojected robust baseline | Low mean divergence, many stable `c`, especially strong at small `c` | Supported |
| `theory + none` beats `inv_t` and `inv_omega_t` convincingly | Pairwise best-stable comparisons strongly favor `theory` | Supported |
| `theory + none` beats all projected variants | Loses to `upper`; only competitive with `oracle` | Not supported |
| Linear TD exhibits robust-to-fast phase transition | Aggregate slopes support it, but many cases do not show both phases clearly by `1e8` | Partially supported |
| Late-stage rate depends on `omega` roughly as `1/omega` | `log D(T)` vs `log omega` slope approaches `-1` by `T=1e8` | Supported |

## Table 1. Global competitiveness of no-projection theory schedules
Using each method's best **stable** `c` on each case.

| Method | Ties global best on `D` | Ties global best on `D+A` | Verdict |
|---|---:|---:|---|
| `theory + none` | 12 / 44 | 11 / 44 | Competitive, not dominant |
| `theory_log2 + none` | 13 / 44 | 6 / 44 | Competitive on `D`, weaker on `D+A` |

## Table 2. Unprojected stability summary over all 44 cases and all 15 `c` values

| Schedule | Mean divergence rate | Mean # stable `c` per case | Median # stable `c` | Cases with at least one stable `c` |
|---|---:|---:|---:|---:|
| `constant` | 0.412 | 8.75 | 8 | 44 / 44 |
| `constant_omega` | 0.129 | 13.07 | 14 | 44 / 44 |
| `inv_omega_t` | 0.657 | 5.05 | 6 | 42 / 44 |
| `inv_sqrt_t` | 0.339 | 9.75 | 10 | 44 / 44 |
| `inv_t` | 0.298 | 10.41 | 11 | 44 / 44 |
| `inv_t_2_3` | 0.322 | 10.02 | 10 | 44 / 44 |
| `theory` | 0.231 | 11.48 | 12 | 44 / 44 |
| `theory_log2` | 0.281 | 10.73 | 11 | 44 / 44 |

### Takeaway

| Observation | Interpretation |
|---|---|
| `constant_omega` has the lowest mean divergence | Most stable unprojected method overall |
| `theory` has lower mean divergence than `inv_t`, `inv_sqrt_t`, `inv_t_2_3`, `inv_omega_t`, `constant` | Strong robust unprojected baseline |
| `theory_log2` is weaker than `theory` on stability | `theory` is the safer of the two theory schedules |

## Table 3. Aggressive stepsize regime: `c = 1e-4`
Recall: `c` is in the denominator, so smaller `c` means larger/more aggressive stepsize.

| Schedule | Mean divergence rate | Stable cases |
|---|---:|---:|
| `constant` | 1.000 | 0 / 44 |
| `constant_omega` | 0.295 | 31 / 44 |
| `inv_omega_t` | 1.000 | 0 / 44 |
| `inv_sqrt_t` | 0.993 | 0 / 44 |
| `inv_t` | 0.909 | 4 / 44 |
| `inv_t_2_3` | 0.945 | 0 / 44 |
| `theory` | 0.451 | 24 / 44 |
| `theory_log2` | 0.907 | 4 / 44 |

## Table 4. Aggressive stepsize regime: `c = 1e-3`

| Schedule | Mean divergence rate | Stable cases |
|---|---:|---:|
| `constant` | 1.000 | 0 / 44 |
| `constant_omega` | 0.182 | 36 / 44 |
| `inv_omega_t` | 1.000 | 0 / 44 |
| `inv_sqrt_t` | 0.729 | 9 / 44 |
| `inv_t` | 0.454 | 24 / 44 |
| `inv_t_2_3` | 0.585 | 14 / 44 |
| `theory` | 0.132 | 38 / 44 |
| `theory_log2` | 0.363 | 28 / 44 |

### Takeaway

| Regime | Best evidence for `theory + none` |
|---|---|
| `c = 1e-4` | Clearly more robust than `inv_t`, `inv_sqrt_t`, `inv_t_2_3`, `inv_omega_t`, `constant` |
| `c = 1e-3` | Still best among classical decaying unprojected schedules; even slightly better than `constant_omega` on stability |

## Table 5. Pairwise best-stable final-error comparisons for `theory + none`
Counts are `better / worse / tie`, comparing each schedule at its own best **stable** `c`.

| Competitor | On `D` | On `D+A` | Interpretation |
|---|---|---|---|
| `constant` | 21 / 18 / 5 | 22 / 18 / 4 | Slight edge to `theory` |
| `constant_omega` | 24 / 15 / 5 | 28 / 14 / 2 | `theory` usually better on final error |
| `inv_omega_t` | 33 / 2 / 7 | 40 / 2 / 0 | Strong win for `theory` |
| `inv_sqrt_t` | 8 / 25 / 11 | 16 / 24 / 4 | `inv_sqrt_t` is a serious competitor |
| `inv_t` | 34 / 4 / 6 | 41 / 3 / 0 | Strong win for `theory` |
| `inv_t_2_3` | 13 / 20 / 11 | 19 / 21 / 4 | `inv_t_2_3` is another serious competitor |
| `theory_log2` | 24 / 9 / 11 | 34 / 8 / 2 | `theory` is better than `theory_log2` |

### Takeaway

| Question | Answer |
|---|---|
| What does `theory + none` beat most clearly? | `inv_t`, `inv_omega_t`, and also `theory_log2` |
| What are the hardest unprojected rivals? | `inv_sqrt_t` and `inv_t_2_3` |
| On which metric does `theory` look better? | `D+A` more than pure `D` |

## Table 6. No projection vs projected versions of the same theory schedule
Again using best stable `c` per case.

| Schedule comparison | On `D` | On `D+A` | Verdict |
|---|---|---|---|
| `theory none` vs `theory oracle` | 20 / 16 / 8 | 21 / 15 / 8 | `none` is genuinely competitive with `oracle` |
| `theory none` vs `theory upper` | 0 / 12 / 32 | 0 / 10 / 34 | `upper` is never worse when non-tied |
| `theory_log2 none` vs `theory_log2 oracle` | 18 / 20 / 6 | 18 / 25 / 1 | roughly competitive on `D`, weaker on `D+A` |
| `theory_log2 none` vs `theory_log2 upper` | 0 / 16 / 28 | 2 / 13 / 29 | `upper` generally better |

### Takeaway

| Claim | Verdict |
|---|---|
| No projection is better than oracle projection | Only partially supported |
| No projection is better than upper-bound projection | Not supported |

## Table 7. Aggregate two-phase slope check
Log-log slope of `D(t)` on the best stable `c` curve.

| Schedule | Early window | Late window | Early target | Late target | Verdict |
|---|---:|---:|---|---|---|
| `theory + none` | -0.619 | -1.056 | near `-1/2` | near `-1` | Qualitatively yes |
| `theory_log2 + none` | -0.492 | -0.966 | very close to `-1/2` | very close to `-1` | Cleanest support |

Windows used:
- early: `10^2` to `10^5`
- late: `10^6` to `10^8`

## Table 8. Casewise strength of the two-phase evidence
A case is counted as matching if:
- early slope is in `[-0.75, -0.25]`
- late slope is in `[-1.25, -0.75]`

| Schedule | Early-window match | Late-window match | Both match | Verdict |
|---|---:|---:|---:|---|
| `theory + none` | 7 / 44 | 15 / 44 | 1 / 44 | Aggregate support only |
| `theory_log2 + none` | 8 / 44 | 11 / 44 | 1 / 44 | Aggregate support only |

### Takeaway

| Statement | Verdict |
|---|---|
| Every case clearly shows two phases by `1e8` | False |
| The dataset, in aggregate, supports a robust-to-fast transition | True |

## Table 9. How the phase transition depends on `omega`
Cases are grouped by `omega` rank within each environment: rank 1 = smallest `omega`, rank 4 = largest.

### `theory + none`

| Omega rank | Median early slope | Median late slope | Interpretation |
|---|---:|---:|---|
| 1 | -0.218 | -0.002 | Hardest cases have not entered fast phase |
| 2 | -0.218 | -0.315 | Still mostly pre-fast-phase |
| 3 | -0.434 | -1.438 | Fast phase clearly visible |
| 4 | -0.946 | -1.283 | Fast phase clearly visible |

### `theory_log2 + none`

| Omega rank | Median early slope | Median late slope | Interpretation |
|---|---:|---:|---|
| 1 | -0.151 | -0.002 | Hardest cases still stuck in robust phase |
| 2 | -0.231 | -0.033 | Fast phase mostly absent |
| 3 | -0.291 | -1.326 | Fast phase visible |
| 4 | -1.047 | -1.303 | Fast phase visible |

### Takeaway

| Observation | Meaning |
|---|---|
| Small `omega` cases have near-zero late slope | `1/(omega t)` regime has not started yet by `1e8` |
| Medium/large `omega` cases have late slope near `-1` | Fast phase is visible once `omega` is large enough |

## Table 10. Fixed-time dependence of final error on `omega`
Regression slope of `log D(T)` on `log omega`, using the best stable `c` curve.

### `theory + none`

| Horizon `T` | Slope of `log D(T)` vs `log omega` |
|---:|---:|
| `1e2` | -0.414 |
| `1e4` | -0.584 |
| `1e6` | -0.763 |
| `1e8` | -1.017 |

### `theory_log2 + none`

| Horizon `T` | Slope of `log D(T)` vs `log omega` |
|---:|---:|
| `1e2` | -0.308 |
| `1e4` | -0.558 |
| `1e6` | -0.768 |
| `1e8` | -1.024 |

### Takeaway

| Time regime | Dependence on `omega` |
|---|---|
| Early time | Present but moderate |
| Mid time | Stronger |
| Late time | Roughly `1/omega` |

## Table 11. Final safe statements for writing

| Safe statement | Why it is safe |
|---|---|
| `theory + no projection` is not universally best | It only ties global best on a subset of cases |
| `theory + no projection` is a strong robust unprojected baseline | Stability numbers and aggressive-`c` behavior support this clearly |
| `theory + no projection` beats `inv_t` and `inv_omega_t` convincingly | Pairwise best-stable comparisons are strongly one-sided |
| `theory_log2 + none` gives the cleanest aggregate evidence for the robust/fast transition | Its median early/late slopes are closest to `-1/2` and `-1` |
| The fast `1/(omega t)` regime is delayed when `omega` is small | Small-`omega` groups do not show late slope near `-1` |
| By `T=1e8`, final error scales approximately like `1/omega` | `log D(T)` vs `log omega` slope is about `-1` |

## Table 12. Statements that should *not* be made

| Unsafe statement | Why unsafe |
|---|---|
| `no projection + theory` is the best method overall | Not supported by best-stable global comparison |
| Every instance shows early `1/sqrt(t)` then late `1/(omega t)` clearly by `1e8` | Only aggregate evidence; casewise evidence is weak |
| Projection is unnecessary because `none` is always better | False against `upper` projection |
| The effect of `omega` is only a constant factor | False; it also changes when the fast phase appears |

## Recommended one-paragraph summary
`theory + no projection` is best interpreted not as a universally dominant algorithm, but as a strong robust baseline within the unprojected family. Its clearest empirical advantage is stability under aggressive stepsizes: at small `c`, it remains stable on far more cases than `inv_t`, `inv_sqrt_t`, `inv_t_2_3`, `inv_omega_t`, and `constant`. On final error, it decisively outperforms `inv_t` and `inv_omega_t`, is competitive with `constant_omega`, and is mainly challenged by `inv_sqrt_t` and `inv_t_2_3`. The data also gives partial support to a robust/fast two-phase picture for linear TD: aggregate slopes are close to `t^{-1/2}` early and `t^{-1}` late, especially for `theory_log2 + none`, but this transition is not uniformly visible across all cases by `1e8` steps. The key moderator is `omega`: small-`omega` cases remain in the slow regime much longer, while larger-`omega` cases enter the fast phase earlier. By the final horizon, the observed dependence of error on `omega` is close to `1/omega`.
