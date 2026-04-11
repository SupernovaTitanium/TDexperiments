# No-Projection Theory TD Review (2026-04-10)

## Data used
- Full run root: `/home/leew0a/codex/TDfullexperiments/td_cxx_logs_full_1e8_n40_44instances_c15_1em7_1e7`
- Scope: 44 TD cases, 8 schedules, 3 projection variants, 15 `c` values, `n_steps=1e8`, `parallel_runs=40`
- Primary metric: `E_D[||Vbar_t - V*||^2]` (`D`)
- Secondary metric: `D+A := E_D[||Vbar_t - V*||^2] + E_A[||Vbar_t - V*||^2]`
- Stability criterion: a `(case, schedule, projection, c)` configuration is called **stable** if its run CSV has `diverged=0` for all 40 Monte Carlo runs.

## What is being tested
The target claim is not “theory/no-projection wins everything”. The target claim is more specific:

1. Does `projection = none` with `schedule = theory` or `theory_log2` show any robust advantage over competing methods?
2. Do the learning curves support a two-phase picture: early `t^{-1/2}` and later `1/(omega t)`?
3. How strongly does convergence depend on `omega`?

## Summary answer
- There is **no evidence** that no-projection theory **uniformly dominates all methods**.
- There **is** evidence that `theory + no projection` is a **strong unprojected robust baseline**:
  - better stability than `inv_t`, `inv_sqrt_t`, `inv_t_2_3`, `inv_omega_t`, and `constant`
  - especially strong at aggressive small-`c` settings
  - often competitive on final `D+A`
- `theory_log2 + no projection` gives the **cleanest aggregate support** for the two-phase rate story.
- The late-stage dependence on `omega` becomes stronger over time and approaches roughly `1/omega` by `T = 1e8` on the final error metric.
- The hardest small-`omega` cases do **not** reliably enter the fast `1/(omega t)` regime by `1e8`; that phase is mainly visible on medium/large-`omega` cases.

## Q1. Evidence for an advantage of `no projection + theory (1 or 2)`

Assumption used here:
- `theory (1 or 2)` means the two theory schedules in the codebase: `theory` and `theory_log2`.

### 1.1 What cannot be claimed
From the full 44-case run, I do **not** see evidence for the statement:
- “`no projection + theory` is the best method overall.”

Using each method's best **stable** `c` on each case:
- `theory + none` ties the global best on `12/44` cases for `D`, `11/44` for `D+A`.
- `theory_log2 + none` ties the global best on `13/44` cases for `D`, `6/44` for `D+A`.

So the correct statement is “competitive”, not “dominant”.

### 1.2 What *is* supported: unprojected robustness
Among the **unprojected** schedules, `theory` is one of the strongest robust baselines.

Overall unprojected stability summary (averaged over all 44 cases and all 15 `c` values):

| schedule | mean divergence rate | mean # stable c per case | median # stable c | all 44 cases have at least one stable c? |
|---|---:|---:|---:|---|
| `constant` | 0.412 | 8.75 | 8 | yes |
| `constant_omega` | 0.129 | 13.07 | 14 | yes |
| `inv_omega_t` | 0.657 | 5.05 | 6 | 42/44 |
| `inv_sqrt_t` | 0.339 | 9.75 | 10 | yes |
| `inv_t` | 0.298 | 10.41 | 11 | yes |
| `inv_t_2_3` | 0.322 | 10.02 | 10 | yes |
| `theory` | 0.231 | 11.48 | 12 | yes |
| `theory_log2` | 0.281 | 10.73 | 11 | yes |

Interpretation:
- `constant_omega` is the most stable unprojected method overall.
- Among the classical decaying schedules, `theory` is the most stable unprojected choice in this run.
- `theory_log2` is somewhat weaker than `theory` on stability.

### 1.3 The strongest concrete advantage: aggressive small-`c` behavior
Recall: in this codebase, `c` is in the denominator of the stepsize, so smaller `c` means a larger/more aggressive stepsize.

At aggressive `c`, `theory + none` is clearly more robust than most other unprojected schedules.

#### At `c = 1e-4`
| schedule | mean divergence rate | stable cases |
|---|---:|---:|
| `constant` | 1.000 | 0/44 |
| `constant_omega` | 0.295 | 31/44 |
| `inv_omega_t` | 1.000 | 0/44 |
| `inv_sqrt_t` | 0.993 | 0/44 |
| `inv_t` | 0.909 | 4/44 |
| `inv_t_2_3` | 0.945 | 0/44 |
| `theory` | 0.451 | 24/44 |
| `theory_log2` | 0.907 | 4/44 |

#### At `c = 1e-3`
| schedule | mean divergence rate | stable cases |
|---|---:|---:|
| `constant` | 1.000 | 0/44 |
| `constant_omega` | 0.182 | 36/44 |
| `inv_omega_t` | 1.000 | 0/44 |
| `inv_sqrt_t` | 0.729 | 9/44 |
| `inv_t` | 0.454 | 24/44 |
| `inv_t_2_3` | 0.585 | 14/44 |
| `theory` | 0.132 | 38/44 |
| `theory_log2` | 0.363 | 28/44 |

This is the cleanest pro-`theory` result in the dataset:
- `theory + none` handles aggressive stepsizes much better than `inv_t`, `inv_sqrt_t`, `inv_t_2_3`, `inv_omega_t`, and `constant`.
- It is even slightly better than `constant_omega` at `c = 1e-3`.

### 1.4 Pairwise final-error comparisons within unprojected methods
Using each unprojected schedule's best **stable** `c` for each case:

#### `theory + none` on `D`
- vs `constant`: `21 better / 18 worse / 5 tie`
- vs `constant_omega`: `24 / 15 / 5`
- vs `inv_omega_t`: `33 / 2 / 7`
- vs `inv_sqrt_t`: `8 / 25 / 11`
- vs `inv_t`: `34 / 4 / 6`
- vs `inv_t_2_3`: `13 / 20 / 11`
- vs `theory_log2`: `24 / 9 / 11`

#### `theory + none` on `D+A`
- vs `constant`: `22 / 18 / 4`
- vs `constant_omega`: `28 / 14 / 2`
- vs `inv_omega_t`: `40 / 2 / 0`
- vs `inv_sqrt_t`: `16 / 24 / 4`
- vs `inv_t`: `41 / 3 / 0`
- vs `inv_t_2_3`: `19 / 21 / 4`
- vs `theory_log2`: `34 / 8 / 2`

Interpretation:
- `theory + none` very clearly beats `inv_t` and `inv_omega_t`.
- It also usually beats `constant_omega` on final error, even though `constant_omega` is more stable.
- Its main unprojected rivals are `inv_sqrt_t` and `inv_t_2_3`.
- On `D+A`, `theory + none` looks stronger than on pure `D`.

### 1.5 No-projection versus projected versions of the same theory schedule
Again using best stable `c` per case:

#### `theory`
- On `D`: `none` vs `oracle` = `20 better / 16 worse / 8 tie`
- On `D+A`: `none` vs `oracle` = `21 / 15 / 8`
- On `D`: `none` vs `upper` = `0 / 12 / 32`
- On `D+A`: `none` vs `upper` = `0 / 10 / 34`

#### `theory_log2`
- On `D`: `none` vs `oracle` = `18 / 20 / 6`
- On `D+A`: `none` vs `oracle` = `18 / 25 / 1`
- On `D`: `none` vs `upper` = `0 / 16 / 28`
- On `D+A`: `none` vs `upper` = `2 / 13 / 29`

Interpretation:
- `none` is genuinely competitive with `oracle`; it is not uniformly worse.
- `upper` projection is much harder for `none` to beat. In many cases it ties `none`, and when it differs it is usually better.
- So if the claim is “no projection is better than projection”, the data only supports that relative to `oracle` in a partial sense, not relative to `upper`.

## Q2. Is there support for the robust/fast two-phase rate story?

Target story:
- early phase: about `t^{-1/2}`
- later phase: about `1/(omega t)`

I tested this on the best stable `c` for `theory + none` and `theory_log2 + none`, using the `D` learning curve.

### 2.1 Aggregate log-log slopes
Two windows were used:
- early window: `10^2` to `10^5`
- late window: `10^6` to `10^8`

#### `theory + none`
- median early slope: `-0.619`
- median late slope: `-1.056`

#### `theory_log2 + none`
- median early slope: `-0.492`
- median late slope: `-0.966`

Interpretation:
- `theory_log2 + none` matches the narrative very well at the **aggregate median** level.
- `theory + none` also supports the same qualitative transition, though the early slope is a bit steeper than `-1/2`.

### 2.2 But the two-phase story is not universal case-by-case
A case is counted as “matching the phase” if:
- early slope is in `[-0.75, -0.25]`
- late slope is in `[-1.25, -0.75]`

#### `theory + none`
- early-window match: `7/44`
- late-window match: `15/44`
- both windows match: `1/44`

#### `theory_log2 + none`
- early-window match: `8/44`
- late-window match: `11/44`
- both windows match: `1/44`

So the honest conclusion is:
- the data supports the robust/fast picture **in aggregate**,
- but not as a clean universal law that every case clearly exhibits by `T = 1e8`.

### 2.3 The phase transition depends strongly on `omega`
For `theory + none`, splitting cases by `omega` rank within each environment:
- rank 1 (smallest `omega`): early slope `-0.218`, late slope `-0.002`
- rank 2: early `-0.218`, late `-0.315`
- rank 3: early `-0.434`, late `-1.438`
- rank 4 (largest `omega`): early `-0.946`, late `-1.283`

For `theory_log2 + none`:
- rank 1: early `-0.151`, late `-0.002`
- rank 2: early `-0.231`, late `-0.033`
- rank 3: early `-0.291`, late `-1.326`
- rank 4: early `-1.047`, late `-1.303`

Interpretation:
- The hard small-`omega` cases mostly have **not** entered the `1/(omega t)` regime by `1e8`.
- The medium/large-`omega` cases often do enter a near-`t^{-1}` late regime.
- So the right statement is:
  - **yes**, there is evidence for a robust-to-fast transition,
  - but **only after enough iterations relative to `omega`**, not uniformly across all cases at the same horizon.

### 2.4 Scaled-curve evidence is weaker than slope evidence
I also checked whether these scaled quantities are approximately flat on their supposed windows:
- early: `sqrt(t) * D(t)`
- late: `omega * t * D(t)`

The median coefficient of variation was not tiny:
- `theory`: early `0.899`, late `0.776`
- `theory_log2`: early `0.888`, late `1.045`

This means the “flat plateau” picture is only approximate. The slope evidence is stronger than the curve-collapse evidence.

## Q3. How does convergence speed depend on `omega`?

### 3.1 Fixed-time dependence strengthens over time
For the best stable `theory + none` curve, regressing `log D(T)` on `log omega` gives:
- `T = 1e2`: slope `-0.414`
- `T = 1e4`: slope `-0.584`
- `T = 1e6`: slope `-0.763`
- `T = 1e8`: slope `-1.017`

For `theory_log2 + none`:
- `T = 1e2`: slope `-0.308`
- `T = 1e4`: slope `-0.558`
- `T = 1e6`: slope `-0.768`
- `T = 1e8`: slope `-1.024`

Interpretation:
- Early on, larger `omega` helps, but only moderately.
- As time grows, the dependence on `omega` becomes much stronger.
- By `T = 1e8`, the final error is roughly scaling like `1/omega` in aggregate.

### 3.2 Operational interpretation
What `omega` changes in practice is not only the final constant. It changes **when** the fast regime begins.

Empirically:
- small `omega` cases stay in the slow/robust phase much longer,
- large `omega` cases reach the fast phase sooner,
- hence at a fixed finite horizon, larger `omega` often looks much better than what early-time asymptotics alone would suggest.

### 3.3 Why I do not rely on fixed threshold hit-times here
I inspected threshold hit-times as a possible speed metric, but they are noisy across the 44 cases because the initial objective scale varies substantially by instance. Some cases start below a chosen threshold at the first logged point, making such thresholds poor cross-instance summaries.

So the more trustworthy cross-instance evidence is:
- piecewise log-log slope,
- fixed-horizon `log D(T)` vs `log omega` regression,
- and best-stable final error comparisons.

## Bottom-line interpretation
If you want the strongest defensible claim from this dataset, it is:

1. `theory + no projection` is **not** the universal best method.
2. It **is** a very strong **unprojected robust baseline**, especially at aggressive stepsizes.
3. The data supports a **two-phase robust/fast picture in aggregate**, with the clearest evidence coming from `theory_log2 + no projection`.
4. The transition to the fast phase is strongly `omega`-dependent.
5. At finite horizon, the main practical effect of small `omega` is that it delays entry into the `1/(omega t)` regime.

## Repro notes
All numbers above came from direct scans of:
- `manifest.tsv`
- `agg_case_*.csv`
- `runs_case_*.csv`

inside:
- `/home/leew0a/codex/TDfullexperiments/td_cxx_logs_full_1e8_n40_44instances_c15_1em7_1e7`
