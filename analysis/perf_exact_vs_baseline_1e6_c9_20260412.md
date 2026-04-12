# Baseline-Exact vs Old Baseline Benchmark (1e6 steps, 11 envs, 4 omegas, 9 c values)

## Configuration

- benchmark root: `/tmp/tdx_benchmark_exact_vs_baseline_1e6_c9_20260412`
- compared binaries: old baseline `/tmp/tdx_bench_suite_20260411/tdx_baseline_d9c4dde` vs current exact `./cpp/tdx`
- environments: `toyexample, E1, ..., E10` (11 env families, 4 omega levels each)
- schedules: `theory, theory_log2, constant_omega, constant, inv_t, inv_sqrt_t, inv_t_2_3, inv_omega_t`
- projections: `none, oracle, upper`
- c sweep assumption: `1e-3,1e-2,1e-1,1,1e1,1e2,1e3,1e4,1e5`
- n_steps: `1e6`
- n_runs: `40`
- threads: `40`

## Timing Summary

| Env | Baseline (s) | Current (s) | Speedup |
|---|---:|---:|---:|
| toyexample | 88 | 41 | 2.146x |
| E1 | 56 | 28 | 2.000x |
| E2 | 68 | 35 | 1.943x |
| E3 | 91 | 35 | 2.600x |
| E4 | 280 | 49 | 5.714x |
| E5 | 257 | 48 | 5.354x |
| E6 | 82 | 31 | 2.645x |
| E7 | 67 | 32 | 2.094x |
| E8 | 68 | 36 | 1.889x |
| E9 | 93 | 37 | 2.514x |
| E10 | 114 | 47 | 2.426x |
| **Total** | **1264** | **419** | **3.017x** |

- mean per-env speedup: `2.848x`
- median per-env speedup: `2.426x`

## Exactness Check

| Env | Total Files | Diff Files | Manifest Diff | Runs Diff | Agg Diff |
|---|---:|---:|---:|---:|---:|
| toyexample | 1729 | 0 | 0 | 0 | 0 |
| E1 | 1729 | 0 | 0 | 0 | 0 |
| E2 | 1729 | 0 | 0 | 0 | 0 |
| E3 | 1729 | 0 | 0 | 0 | 0 |
| E4 | 1729 | 0 | 0 | 0 | 0 |
| E5 | 1729 | 0 | 0 | 0 | 0 |
| E6 | 1729 | 0 | 0 | 0 | 0 |
| E7 | 1729 | 0 | 0 | 0 | 0 |
| E8 | 1729 | 0 | 0 | 0 | 0 |
| E9 | 1729 | 0 | 0 | 0 | 0 |
| E10 | 1729 | 0 | 0 | 0 | 0 |

- all outputs identical: `yes`

## Output Roots

- toyexample: baseline `/tmp/tdx_benchmark_exact_vs_baseline_1e6_c9_20260412/out_baseline_toyexample/toyexample_20260412_184637` ; current `/tmp/tdx_benchmark_exact_vs_baseline_1e6_c9_20260412/out_current_toyexample/toyexample_20260412_184805`
- E1: baseline `/tmp/tdx_benchmark_exact_vs_baseline_1e6_c9_20260412/out_baseline_E1/E1_20260412_184846` ; current `/tmp/tdx_benchmark_exact_vs_baseline_1e6_c9_20260412/out_current_E1/E1_20260412_184942`
- E2: baseline `/tmp/tdx_benchmark_exact_vs_baseline_1e6_c9_20260412/out_baseline_E2/E2_20260412_185010` ; current `/tmp/tdx_benchmark_exact_vs_baseline_1e6_c9_20260412/out_current_E2/E2_20260412_185118`
- E3: baseline `/tmp/tdx_benchmark_exact_vs_baseline_1e6_c9_20260412/out_baseline_E3/E3_20260412_185153` ; current `/tmp/tdx_benchmark_exact_vs_baseline_1e6_c9_20260412/out_current_E3/E3_20260412_185324`
- E4: baseline `/tmp/tdx_benchmark_exact_vs_baseline_1e6_c9_20260412/out_baseline_E4/E4_20260412_185359` ; current `/tmp/tdx_benchmark_exact_vs_baseline_1e6_c9_20260412/out_current_E4/E4_20260412_185839`
- E5: baseline `/tmp/tdx_benchmark_exact_vs_baseline_1e6_c9_20260412/out_baseline_E5/E5_20260412_185928` ; current `/tmp/tdx_benchmark_exact_vs_baseline_1e6_c9_20260412/out_current_E5/E5_20260412_190345`
- E6: baseline `/tmp/tdx_benchmark_exact_vs_baseline_1e6_c9_20260412/out_baseline_E6/E6_20260412_190433` ; current `/tmp/tdx_benchmark_exact_vs_baseline_1e6_c9_20260412/out_current_E6/E6_20260412_190555`
- E7: baseline `/tmp/tdx_benchmark_exact_vs_baseline_1e6_c9_20260412/out_baseline_E7/E7_20260412_190626` ; current `/tmp/tdx_benchmark_exact_vs_baseline_1e6_c9_20260412/out_current_E7/E7_20260412_190733`
- E8: baseline `/tmp/tdx_benchmark_exact_vs_baseline_1e6_c9_20260412/out_baseline_E8/E8_20260412_190805` ; current `/tmp/tdx_benchmark_exact_vs_baseline_1e6_c9_20260412/out_current_E8/E8_20260412_190913`
- E9: baseline `/tmp/tdx_benchmark_exact_vs_baseline_1e6_c9_20260412/out_baseline_E9/E9_20260412_190949` ; current `/tmp/tdx_benchmark_exact_vs_baseline_1e6_c9_20260412/out_current_E9/E9_20260412_191122`
- E10: baseline `/tmp/tdx_benchmark_exact_vs_baseline_1e6_c9_20260412/out_baseline_E10/E10_20260412_191159` ; current `/tmp/tdx_benchmark_exact_vs_baseline_1e6_c9_20260412/out_current_E10/E10_20260412_191353`

