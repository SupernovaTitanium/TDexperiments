# Corrected TD Instance Summary (toyexample, E1~E12)

Date: 2026-04-04

Source: `cpp/tdx.cpp`
Smoke verification runs: `verification/new_instance_smoke/*/manifest.tsv`

## 1. Core Corrections Applied

1. **`phi_\infty^2` normalization**: every instance is normalized to satisfy `max_s ||phi(s)||_2^2 = 1` (numerically `~1`).
2. **Stepsize scaling uses denominator `c`**:
   - `constant`: `alpha_t = 1/c`
   - `inv_t`: `alpha_t = 1 / (c (t+t0))`
   - `inv_sqrt_t`: `alpha_t = 1 / (c sqrt(t+t0))`
   - `inv_omega_t`: `alpha_t = 1 / (c omega (t+t0))`
   - `theory`: `alpha_t = 1 / (c * phi_max_sq * log(T) * log(t+3) * sqrt(t+1))`
3. **4 omega levels per environment (feature-side controls)**:
   - `toyexample, E5, E6, E8, E9`: sweep `feature_omega_beta in {1e-3,1e-2,1e-1,1}`
   - `E1, E2, E3, E4, E7, E10, E11, E12`: sweep `eps2 in {1e-4,1e-2,1e-1,1}`
4. **Duplicate instance removal by omega**: keep unique cases by relative tolerance `1e-6`. Current 13 envs each keep 4 unique omega cases.

## 2. Environment-Level Summary

| Env | Cases Kept | omega_min | omega_max | phi_max_sq_min | phi_max_sq_max |
|---|---:|---:|---:|---:|---:|
| toyexample | 4 | 5.69771043773e-10 | 0.00017524271656 | 1 | 1 |
| E1 | 4 | 0.00500000005 | 0.01 | 1 | 1 |
| E2 | 4 | 2.49999996875e-11 | 0.000954915028125 | 1 | 1 |
| E3 | 4 | 2.49999996875e-11 | 0.000954915028125 | 1 | 1 |
| E4 | 4 | 1.66666664583e-11 | 0.00063661001875 | 1 | 1 |
| E5 | 4 | 5e-10 | 0.0005 | 1 | 1 |
| E6 | 4 | 8.33333333333e-11 | 8.33333333333e-05 | 1 | 1 |
| E7 | 4 | 0.00500000005 | 0.01 | 1 | 1 |
| E8 | 4 | 5e-09 | 0.005 | 1 | 1 |
| E9 | 4 | 2.56833816894e-09 | 0.00173785398504 | 1 | 1 |
| E10 | 4 | 0.002500000025 | 0.00375 | 1 | 1 |
| E11 | 4 | 3.466666632e-11 | 0.00173333333333 | 1 | 1 |
| E12 | 4 | 9.9999999e-11 | 0.005 | 1 | 1 |

## 3. Detailed Omega Grid per Environment

### toyexample

| case_id | control | value | omega | kappa | phi_max_sq | tau_proxy |
|---|---|---:|---:|---:|---:|---:|
| 0001 | feature_omega_beta | 1e-3 | 5.69771043773e-10 | 5459085.70631 | 1 | 156.614800339 |
| 0002 | feature_omega_beta | 1e-2 | 5.69725598859e-08 | 54603.9103914 | 1 | 156.614800339 |
| 0003 | feature_omega_beta | 1e-1 | 5.65217088486e-06 | 559.234471857 | 1 | 156.614800339 |
| 0004 | feature_omega_beta | 1.0 | 0.00017524271656 | 23.8494127276 | 1 | 156.614800339 |

### E1

| case_id | control | value | omega | kappa | phi_max_sq | tau_proxy |
|---|---|---:|---:|---:|---:|---:|
| 0001 | eps2 | 1e-4 | 0.00500000005 | 1 | 1 | 1 |
| 0002 | eps2 | 1e-2 | 0.0050005 | 1 | 1 | 1 |
| 0003 | eps2 | 1e-1 | 0.00505 | 1 | 1 | 1 |
| 0004 | eps2 | 1.0 | 0.01 | 1 | 1 | 1 |

### E2

| case_id | control | value | omega | kappa | phi_max_sq | tau_proxy |
|---|---|---:|---:|---:|---:|---:|
| 0001 | eps2 | 1e-4 | 2.49999996875e-11 | 400000002 | 1 | 1 |
| 0002 | eps2 | 1e-2 | 2.49968753125e-07 | 40002.000075 | 1 | 1 |
| 0003 | eps2 | 1e-1 | 2.46905944462e-05 | 402.007512484 | 1 | 1 |
| 0004 | eps2 | 1.0 | 0.000954915028125 | 6.85410196625 | 1 | 1 |

### E3

| case_id | control | value | omega | kappa | phi_max_sq | tau_proxy |
|---|---|---:|---:|---:|---:|---:|
| 0001 | eps2 | 1e-4 | 2.49999996875e-11 | 400000002 | 1 | 1 |
| 0002 | eps2 | 1e-2 | 2.49968753125e-07 | 40002.000075 | 1 | 1 |
| 0003 | eps2 | 1e-1 | 2.46905944462e-05 | 402.007512484 | 1 | 1 |
| 0004 | eps2 | 1.0 | 0.000954915028125 | 6.85410196625 | 1 | 1 |

### E4

| case_id | control | value | omega | kappa | phi_max_sq | tau_proxy |
|---|---|---:|---:|---:|---:|---:|
| 0001 | eps2 | 1e-4 | 1.66666664583e-11 | 400000002 | 1 | 160799772467 |
| 0002 | eps2 | 1e-2 | 1.66645835416e-07 | 40002.000075 | 1 | 160799772467 |
| 0003 | eps2 | 1e-1 | 1.64603962974e-05 | 402.007512484 | 1 | 160799772467 |
| 0004 | eps2 | 1.0 | 0.00063661001875 | 6.85410196625 | 1 | 160799772467 |

### E5

| case_id | control | value | omega | kappa | phi_max_sq | tau_proxy |
|---|---|---:|---:|---:|---:|---:|
| 0001 | feature_omega_beta | 1e-3 | 5e-10 | 1000000 | 1 | 2063.31047213 |
| 0002 | feature_omega_beta | 1e-2 | 5e-08 | 10000 | 1 | 2063.31047213 |
| 0003 | feature_omega_beta | 1e-1 | 5e-06 | 100 | 1 | 2063.31047213 |
| 0004 | feature_omega_beta | 1.0 | 0.0005 | 1 | 1 | 2063.31047213 |

### E6

| case_id | control | value | omega | kappa | phi_max_sq | tau_proxy |
|---|---|---:|---:|---:|---:|---:|
| 0001 | feature_omega_beta | 1e-3 | 8.33333333333e-11 | 1000000 | 1 | inf |
| 0002 | feature_omega_beta | 1e-2 | 8.33333333333e-09 | 10000 | 1 | inf |
| 0003 | feature_omega_beta | 1e-1 | 8.33333333333e-07 | 100 | 1 | inf |
| 0004 | feature_omega_beta | 1.0 | 8.33333333333e-05 | 1 | 1 | inf |

### E7

| case_id | control | value | omega | kappa | phi_max_sq | tau_proxy |
|---|---|---:|---:|---:|---:|---:|
| 0001 | eps2 | 1e-4 | 0.00500000005 | 1 | 1 | 1 |
| 0002 | eps2 | 1e-2 | 0.0050005 | 1 | 1 | 1 |
| 0003 | eps2 | 1e-1 | 0.00505 | 1 | 1 | 1 |
| 0004 | eps2 | 1.0 | 0.01 | 1 | 1 | 1 |

### E8

| case_id | control | value | omega | kappa | phi_max_sq | tau_proxy |
|---|---|---:|---:|---:|---:|---:|
| 0001 | feature_omega_beta | 1e-3 | 5e-09 | 1000000 | 1 | 5250.67467906 |
| 0002 | feature_omega_beta | 1e-2 | 5e-07 | 10000 | 1 | 5250.67467906 |
| 0003 | feature_omega_beta | 1e-1 | 5e-05 | 100 | 1 | 5250.67467906 |
| 0004 | feature_omega_beta | 1.0 | 0.005 | 1 | 1 | 5250.67467906 |

### E9

| case_id | control | value | omega | kappa | phi_max_sq | tau_proxy |
|---|---|---:|---:|---:|---:|---:|
| 0001 | feature_omega_beta | 1e-3 | 2.56833816894e-09 | 2124886.77539 | 1 | inf |
| 0002 | feature_omega_beta | 1e-2 | 2.56825537661e-07 | 21250.2352313 | 1 | inf |
| 0003 | feature_omega_beta | 1e-1 | 2.55996427261e-05 | 213.878516585 | 1 | inf |
| 0004 | feature_omega_beta | 1.0 | 0.00173785398504 | 4.63543348483 | 1 | inf |

### E10

| case_id | control | value | omega | kappa | phi_max_sq | tau_proxy |
|---|---|---:|---:|---:|---:|---:|
| 0001 | eps2 | 1e-4 | 0.002500000025 | 2.99999994 | 1 | 1 |
| 0002 | eps2 | 1e-2 | 0.002500249975 | 2.99940011998 | 1 | 1 |
| 0003 | eps2 | 1e-1 | 0.00252475247525 | 2.94117647059 | 1 | 1 |
| 0004 | eps2 | 1.0 | 0.00375 | 1 | 1 | 1 |

### E11

| case_id | control | value | omega | kappa | phi_max_sq | tau_proxy |
|---|---|---:|---:|---:|---:|---:|
| 0001 | eps2 | 1e-4 | 3.466666632e-11 | 288461538.462 | 1 | 1054.47898637 |
| 0002 | eps2 | 1e-2 | 3.46632003466e-07 | 28846.1538462 | 1 | 1054.47898637 |
| 0003 | eps2 | 1e-1 | 3.43234323432e-05 | 288.461538462 | 1 | 1054.47898637 |
| 0004 | eps2 | 1.0 | 0.00173333333333 | 2.88461538462 | 1 | 1054.47898637 |

### E12

| case_id | control | value | omega | kappa | phi_max_sq | tau_proxy |
|---|---|---:|---:|---:|---:|---:|
| 0001 | eps2 | 1e-4 | 9.9999999e-11 | 100000000 | 1 | 500 |
| 0002 | eps2 | 1e-2 | 9.99900009999e-07 | 10000 | 1 | 500 |
| 0003 | eps2 | 1e-1 | 9.90099009901e-05 | 100 | 1 | 500 |
| 0004 | eps2 | 1.0 | 0.005 | 1 | 1 | 500 |

## 4. Reproduce This Summary

```bash
make -C cpp tdx
for env in toyexample E1 E2 E3 E4 E5 E6 E7 E8 E9 E10 E11 E12; do
  ./cpp/tdx sweep --env "$env" --n_steps 10 --n_runs 1 --threads 1 \
    --skip_plots --schedules constant --projections none --base_values 1 \
    --outdir verification/new_instance_smoke
done
```
