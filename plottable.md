# plottable.md (v2)

This file defines what `scripts/plot_suite_v2.py` and `scripts/generate_embedded_report_v2.py` produce.

## Symbols
- `E`: number of environments (`env_id`), e.g. `toyexample, E1..E10` => `E=11`.
- `C_e`: number of cases in environment `e` (same as number of omega levels in that env).
- `M`: number of methods = `|schedules| * |projections|`.
- `S`: number of `c` values (scale sweep size).

Current common full setting:
- schedules = `{theory, inv_t, inv_sqrt_t, inv_omega_t, constant}` => `5`
- projections = `{none, oracle, upper}` => `3`
- therefore `M = 5 * 3 = 15`
- common `c` sweep examples:
  - short: `{1e-3, 1e-1, 1e1}` => `S=3`
  - full: `1e-5..1e3` half-decade => `S=17`

## Plot Families (per environment)

### 1) Best curves by c (metric D)
- filename pattern:
  - `{env}__bestcurves_by_c__metric-D__omega-grid-{rows}x{cols}.png`
- figure meaning:
  - each subplot = one omega/case
  - each line = one method `(schedule, projection)`
  - for each method, choose best `c` by minimal final `D`

### 1.5) Best curves by c (metric D+A)
- filename pattern:
  - `{env}__bestcurves_by_c__metric-DA__omega-grid-{rows}x{cols}.png`
- same as #1 but best `c` and y-axis use final `D+A`

### 2) Method final grid (ratio/divergence/D/D+A vs c)
- filename pattern:
  - `{env}__algo-finalgrid__method-{method_id}__rows-omega__cols-ratio-div-D-DA.png`
- one figure per method
- subplot layout is `(C_e, 4)`:
  - rows: omega/case
  - columns: ratio / divergence / final D / final D+A

### 3) Method learning curves by c (metric D)
- filename pattern:
  - `{env}__algo-curves-by-c__metric-D__method-{method_id}__omega-grid-{rows}x{cols}.png`
- one figure per method
- each subplot = one omega/case
- each line = one `c`
- x = timestep (log), y = suboptimality `D` (log)

### 4) Method learning curves by c (metric D+A)
- filename pattern:
  - `{env}__algo-curves-by-c__metric-DA__method-{method_id}__omega-grid-{rows}x{cols}.png`
- same as #3 but y = `D+A`

### 5) Per-omega all-method best-c overlay (metric D)
- filename pattern:
  - `{env}__omega-{idx}--{omega}__methods-bestc__metric-D.png`
- one figure per omega/case
- each line = one method with its best `c` under metric `D`

### 6) Per-omega all-method best-c overlay (metric D+A)
- filename pattern:
  - `{env}__omega-{idx}--{omega}__methods-bestc__metric-DA.png`
- same as #5 but best `c` and y-axis use `D+A`

### 7) Omega vs final error scatter per method (metric D)
- filename pattern:
  - `{env}__omega_final_error_D__method-{method_id}.png`
- one figure per method
- x = omega level
- y = final `D`
- point color = `c`

### 8) Omega vs final error scatter per method (metric D+A)
- filename pattern:
  - `{env}__omega_final_error_DA__method-{method_id}.png`
- same as #7 but y = final `D+A`

### 9) Inventory
- filename pattern:
  - `plot_inventory_v2.tsv`
- one TSV listing all PNG generated for that env run directory.

## Per-environment image count formula
For an environment with `C_e` cases and `M` methods:
- family #1/#1.5: `2`
- family #2: `M`
- family #3/#4: `2M`
- family #5/#6: `2C_e`
- family #7/#8: `2M`

Total PNG per environment:
- `N_env = 2 + M + 2M + 2C_e + 2M = 2 + 5M + 2C_e`

With current default (`M=15`, `C_e=4`):
- `N_env = 2 + 75 + 8 = 85`

## Total count across all environments
- `N_total = sum_e (2 + 5M + 2C_e)`
- if all envs have same `C` cases:
  - `N_total = E * (2 + 5M + 2C)`

Example with `E=11`, `M=15`, `C=4`:
- `N_total = 11 * 85 = 935` PNG.

## Extra report assets (outside plot_suite_v2)
- `scripts/generate_embedded_report_v2.py` embeds all plot PNG and can additionally embed:
  - instance structure images from `<root>/instance_structure_plots/*.png`
  - alpha table from `verification/summary_instance_44cases.tsv` (or custom `--summary-tsv`).
