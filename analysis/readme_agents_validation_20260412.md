# README / AGENTS Validation (2026-04-12)

## Goal

Check whether the repo-local `README.md` and `AGENTS.md` match the current repository code and workflow.

## Files checked

- `README.md`
- `AGENTS.md`
- `cpp/tdx.cpp`
- `cpp/Makefile`
- `scripts/plot_suite_v2.py`
- `scripts/generate_embedded_report_v2.py`
- `scripts/run_full_1e6_all_algos_44instances_n36.sh`
- `analysis/perf_exact_vs_baseline_1e6_c9_20260412.md`
- `analysis/final_exact_revalidation_20260412.md`

## Verified items

1. The primary workflow described in the docs matches the repo.
   - Build with `make -C cpp`.
   - Run experiments with `./cpp/tdx`.
   - Plot with `scripts/plot_suite_v2.py`.
   - Generate self-contained HTML with `scripts/generate_embedded_report_v2.py`.

2. The supported environment ids match code.
   - `toyexample`, `E1`, `E2`, `E3`, `E4`, `E5`, `E6`, `E7`, `E8`, `E9`, `E10`.

3. The supported schedules match code.
   - `theory`, `theory_log2`, `inv_t`, `inv_sqrt_t`, `inv_t_2_3`, `inv_omega_t`, `constant_omega`, `constant`.

4. The supported projections match code.
   - `none`, `oracle`, `upper`.

5. The projection-radius formulas in the docs match code.
   - oracle: `sqrt(theta_star_sq)`
   - upper: `2 * r_max / (sqrt(omega) * (1 - gamma)^(3/2))`

6. Plotting-environment guidance matches code.
   - `.venv_plot` exists in the repo.
   - `cpp/tdx.cpp` auto-detects `.venv_plot/bin/python` via `detect_plot_python_executable()`.

7. Embedded-report guidance matches code.
   - `scripts/generate_embedded_report_v2.py` picks the latest run directory per environment when given a multi-run root.

8. Exactness-first wording matches the current branch state.
   - `analysis/final_exact_revalidation_20260412.md` documents restored full exactness.
   - `analysis/perf_exact_vs_baseline_1e6_c9_20260412.md` documents exactness-preserving speedup.

## Corrections made

Two wording fixes were applied.

1. Replaced the overly loose phrase `default 4-case omega sweep` with the actual default sweep logic from code.
   - `feature_omega_beta` is swept for `toyexample`, `E4`, `E5`, `E6`, `E7`.
   - `eps2` is swept for `E1`, `E2`, `E3`, `E8`, `E9`, `E10`.

2. Added an explicit note that `./cpp/tdx --plot_python` auto-detects `.venv_plot/bin/python` before falling back to `python3`.

## Conclusion

After these wording fixes, `README.md` and `AGENTS.md` are consistent with the current repository code and with the exactness-preserving accelerated default implementation.
