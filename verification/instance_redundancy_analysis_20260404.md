# Instance Redundancy Analysis (52-case grid)

Date: 2026-04-04

Source table: `verification/td_instance_omega_grid_20260404.tsv`

## 1. Exact Redundancy (Strict)

Criterion: same `(omega, tau_proxy)` up to relative tolerance `1e-10`.

- group size 2: E1(eps2=1e-4) ; E7(eps2=1e-4)
- group size 2: E1(eps2=1e-2) ; E7(eps2=1e-2)
- group size 2: E1(eps2=1e-1) ; E7(eps2=1e-1)
- group size 2: E1(eps2=1.0) ; E7(eps2=1.0)
- group size 2: E2(eps2=1e-4) ; E3(eps2=1e-4)
- group size 2: E2(eps2=1e-2) ; E3(eps2=1e-2)
- group size 2: E2(eps2=1e-1) ; E3(eps2=1e-1)
- group size 2: E2(eps2=1.0) ; E3(eps2=1.0)

Strict-dedup result: keep **44**, remove **8**.

## 2. Difficulty-Bin Redundancy

Difficulty bin = `(floor(log10(omega)), tau_regime)` where `tau_regime in {fast<=1e1, mid<=1e3, slow<=1e6, vslow>1e6, inf}`.

Total bins: **32** from 52 cases.

| omega_decade | tau_regime | count | representative (min kappa) |
|---:|---|---:|---|
| -11 | fast<=1e1 | 2 | E2(eps2=1e-4) |
| -11 | inf | 1 | E6(feature_omega_beta=1e-3) |
| -11 | mid<=1e3 | 1 | E12(eps2=1e-4) |
| -11 | slow<=1e6 | 1 | E11(eps2=1e-4) |
| -11 | vslow>1e6 | 1 | E4(eps2=1e-4) |
| -10 | mid<=1e3 | 1 | toyexample(feature_omega_beta=1e-3) |
| -10 | slow<=1e6 | 1 | E5(feature_omega_beta=1e-3) |
| -9 | inf | 2 | E6(feature_omega_beta=1e-2) |
| -9 | slow<=1e6 | 1 | E8(feature_omega_beta=1e-3) |
| -8 | mid<=1e3 | 1 | toyexample(feature_omega_beta=1e-2) |
| -8 | slow<=1e6 | 1 | E5(feature_omega_beta=1e-2) |
| -7 | fast<=1e1 | 2 | E2(eps2=1e-2) |
| -7 | inf | 2 | E6(feature_omega_beta=1e-1) |
| -7 | mid<=1e3 | 1 | E12(eps2=1e-2) |
| -7 | slow<=1e6 | 2 | E8(feature_omega_beta=1e-2) |
| -7 | vslow>1e6 | 1 | E4(eps2=1e-2) |
| -6 | mid<=1e3 | 1 | toyexample(feature_omega_beta=1e-1) |
| -6 | slow<=1e6 | 1 | E5(feature_omega_beta=1e-1) |
| -5 | fast<=1e1 | 2 | E2(eps2=1e-1) |
| -5 | inf | 2 | E6(feature_omega_beta=1.0) |
| -5 | mid<=1e3 | 1 | E12(eps2=1e-1) |
| -5 | slow<=1e6 | 2 | E8(feature_omega_beta=1e-1) |
| -5 | vslow>1e6 | 1 | E4(eps2=1e-1) |
| -4 | fast<=1e1 | 2 | E2(eps2=1.0) |
| -4 | mid<=1e3 | 1 | toyexample(feature_omega_beta=1.0) |
| -4 | slow<=1e6 | 1 | E5(feature_omega_beta=1.0) |
| -4 | vslow>1e6 | 1 | E4(eps2=1.0) |
| -3 | fast<=1e1 | 10 | E1(eps2=1e-4) |
| -3 | inf | 1 | E9(feature_omega_beta=1.0) |
| -3 | mid<=1e3 | 1 | E12(eps2=1.0) |
| -3 | slow<=1e6 | 2 | E8(feature_omega_beta=1.0) |
| -2 | fast<=1e1 | 2 | E1(eps2=1.0) |

Difficulty-bin dedup result: keep **32**, remove **20**.

## 3. Recommended Pruning Options

1. Conservative (safe): remove only strict duplicates -> 52 -> 44.
2. Difficulty-focused: keep one per difficulty bin -> 52 -> 32.
3. If you still want environment diversity, start from 44 and only additionally remove E10(4) + E8(4) -> 36.

## 4. Suggested Keep/Drop (Conservative 44-case)

- Drop all `E3` (4 cases), keep `E2` instead.
- Drop all `E7` (4 cases), keep `E1` instead.
- Keep others unchanged.
