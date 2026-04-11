# Current Settings and Refactor Plan (2026-04-05)

## 1) Current Detailed Settings

### 1.1 Core runtime (`cpp/tdx`)
- Source of truth: `cpp/tdx.cpp`
- Main constants:
  - `kDivergenceThreshold = 1e20`
  - `kEps = 1e-12`
- Default runner config:
  - `mode = sweep`
  - `env_id = toyexample`
  - `n_steps = 10,000,000`
  - `n_runs = 48`
  - `base_values = [1e-3, 1e-2, 1e-1, 1, 10]`
  - `schedules = [theory, inv_t, inv_sqrt_t, inv_omega_t, constant]`
  - `projections = [none, oracle, upper]`
  - `t0 = 0`
  - `dense_prefix = 100`
  - `log_step_decades = 0.01`
  - `dedup_cases_by_omega = true`
  - `omega_dedup_rel_tol = 1e-6`

### 1.2 Step-size definitions (all `c` in denominator)
For `alpha_t = alpha_t(c, t, n_steps, omega, phi_max_sq)`:
- `theory`:
  - `alpha_t = 1 / ( c * max(phi_max_sq,1e-12) * max(log(n_steps),1) * log(t+3) * sqrt(t+1) )`
- `constant`:
  - `alpha_t = 1 / c`
- `inv_t`:
  - `alpha_t = 1 / ( c * max(1, t+t0) )`
- `inv_sqrt_t`:
  - `alpha_t = 1 / ( c * sqrt(max(1, t+t0)) )`
- `inv_omega_t`:
  - `alpha_t = 1 / ( c * max(omega,1e-12) * max(1, t+t0) )`

### 1.3 Projection settings
- `none`: unprojected
- `oracle`:
  - `R_oracle = ||theta*||_2`
- `upper`:
  - `R_upper = 2*r_max / (sqrt(omega) * (1-gamma)^(3/2))`

### 1.4 Feature norm control
- `Phi` is always normalized by `normalize_phi_infty_sq(...)` so that:
  - `max_s ||phi(s)||_2^2 ~= 1`

### 1.5 RNG
- SplitMix64 deterministic stream (`SplitMix64Rng`)
- stable seed mixing via `(param_value bits, run_idx, salt)` in `stable_seed(...)`

### 1.6 Instance set
- Active env IDs: `toyexample, E1..E10` (11 envs)
- Case sweep is metadata-driven from `manifest.tsv`; plotting/report does not assume fixed case count.

### 1.7 Mixing estimate for instance reports
- Source of truth: `cpp/tdmix_kstep.cpp`
- k-step Dobrushin contraction
- current report defaults:
  - `K = 256`
  - `eps = 1e-6`
- summary generator:
  - `scripts/generate_summary_instance_md.py`
  - output TSV default: `verification/summary_instance_44cases.tsv`

### 1.8 Plot/report pipeline (v2)
- Plot entrypoint:
  - `scripts/plot_suite_v2.py`
- Report entrypoint:
  - `scripts/generate_embedded_report_v2.py`
- Supported dynamic axes:
  - variable omega count (no fixed 4)
  - variable cases per env
  - variable method count (`|schedules|*|projections|`)
  - variable `c` count
- Per-env plot count formula:
  - let `M = #methods`, `C_e = #cases in env e`
  - `N_env = 2 + 5M + 2C_e`
  - current common full case (`M=15`, `C_e=4`): `N_env = 85`

## 2) Removed Unnecessary Code (done)

### 2.1 Deleted obsolete plotting/report scripts
- deleted: `scripts/plot_learning_curves.py`
- deleted: `scripts/plot_divergence_parity.py`
- deleted: `scripts/plot_omega_tau_study.py`
- deleted: `scripts/generate_cxx_html_report.py`

### 2.2 Deleted redundant C++ environment builders
- removed unused legacy functions from `cpp/tdx.cpp`:
  - `build_e3(...)`
  - `build_e7(...)`
- reason:
  - current renumbered mapping path already uses `relabel_environment(build_e4(...), "E3", ...)` and `relabel_environment(build_e9(...), "E7", ...)`

## 3) Scalability updates for future omega / instance growth (done)
- `plot_suite_v2.py` already uses dynamic grid layout (`grid_shape`) and does not hardcode 4 omegas.
- `generate_embedded_report_v2.py` now supports:
  - `--root` as a run root (many env dirs), or
  - `--root` as a single run dir containing `manifest.tsv`.
- `scripts/run_full_1e7_theory_all_envs.sh` now supports `ENVS_CSV` override.
- `scripts/run_full_1e9_nonzero_theta_all_envs.sh` now supports `ENVS_CSV` override.
- `cpp/tdx --plot_python` now calls v2 scripts directly:
  - `plot_suite_v2.py`
  - `generate_embedded_report_v2.py`

## 4) Refactor Code Plan (next)

### Phase A: configuration unification
- Introduce one shared experiment spec file (YAML/JSON/TOML) for:
  - env list
  - schedule list
  - projection list
  - c grid
  - steps/runs/threads
- Make bash wrappers read this spec so no duplicated defaults.

### Phase B: plotting modularization
- Split `plot_suite_v2.py` into modules:
  - data loader/cache
  - metric calculators
  - figure builders by family
  - naming + inventory
- Add a strict schema check for `manifest.tsv`/`agg_*.csv`/`runs_*.csv`.

### Phase C: report modularization
- Move embedded HTML template to a dedicated template file.
- Add optional filtering knobs:
  - include/exclude figure families
  - include/exclude structure plots
  - limit env/case subset

### Phase D: CI-grade validation
- Add a fast smoke target:
  - tiny run (`n_steps<=200`, `n_runs<=2`)
  - auto-generate plots/report
  - assert expected file patterns exist
- Add regression checks for dynamic count formula:
  - verify `N_env = 2 + 5M + 2C_e` from produced inventory.

### Phase E: documentation consolidation
- Keep one canonical plotting spec (`plottable.md`) and remove historical references in old verification docs.
- Keep one canonical execution doc (`README.md`) for v2 pipeline only.
