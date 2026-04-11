# summary_instance.md (44 renumbered TD instances)

Date: 2026-04-04

## A. Reproducibility + Definitions

資料來源
- Master table: `/home/leew0a/codex/TDfullexperiments/verification/summary_instance_44cases.tsv`
- Matrix dump root: `/home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404`
- Generator: `scripts/generate_summary_instance_md.py`
- k-step estimator: `cpp/tdmix_kstep` with `K=256`, `eps=1e-6`

統一定義
- `phi_infty^2 = max_s ||phi(s)||_2^2`（本批 44 cases 都被正規化到接近 1）。
- Stepsize scaling 全部用分母形式：`alpha_t = 1 / (c * g(t))`。
- `omega`: `G` 最小特徵值；`kappa=lambda_max(G)/omega`。
- `lambda_min((A+A^T)/2)`: 其中 `A = Phi^T D (I-gamma P) Phi` 為 standard TD mean matrix。
- `tau_proxy`: 由 transition mixing 代理量（由 C++ 主程式輸出）。
- `alpha_hat`: k-step Dobrushin 表中 `best_k` 那列的 `alpha_k = delta(P^k)^(1/k)`。
- `1/(1-alpha_hat)`: 即 `tau_alpha_hat`（若 `alpha_hat=1` 則為 `inf`）。
- `C_hat`: `best_k` 那列的 `C_k=max_{0<=r<k} delta(P^r)`。
- `t_mix_upper_alpha`: `best_k` 那列的理論 upper bound `t_mix_upper_k(eps)`。
- Projection 半徑：`R_oracle = ||theta^*||_2`，`R_upper = 2*r_max/(sqrt(omega)*(1-gamma)^(3/2))`。
- Objective-A 對應 C++ 內 `A2=(1-gamma)Diag(D)+gamma*S`（`S` 為對稱化 Dirichlet 結構），紀錄欄位為 `E_A[||Vbar_t-V*||^2]`。

- 編號規則已更新：刪除 legacy `E3`、`E7` 後，後續環境遞補為 `E1..E10`。

## B. Environment-Level TD Instance Definitions

以下先給每個 environment 的生成規則；44 個 case 是在同一規則下改 `eps2` 或 `feature_omega_beta` 的 4-level sweep。

### toyexample

- `gamma` (all cases): `0.99`
- State/action-free Markov chain with `n=50`, `d=5`, `gamma=0.99`.
- Transition: `P(i,i)=0.1`, `P(i,i+1 mod 50)=0.6`, `P(i,i-1 mod 50)=0.3`.
- Feature: random `Phi[s,j] ~ Uniform(0,10)` from SplitMix64(seed=114514), then `feature_omega_beta` scales columns `j>=2`, then global `phi_infty^2` normalization.

### E1

- `gamma` (all cases): `0.99`
- 2-state alternating chain (`n=2`, `d=1`, `gamma=0.99`).
- Transition: `P=[[eps1,1-eps1],[1-eps1,eps1]]`, default `eps1=1e-3`.
- Feature: `phi(1)=eps2/sqrt(1+eps2^2)`, `phi(2)=1/sqrt(1+eps2^2)` then normalized to `phi_infty^2=1`.

### E2

- `gamma` (all cases): `0.99`
- 2-state sticky chain (`n=2`, `d=2`, `gamma=0.99`).
- Transition: `P=[[1-eps1,eps1],[eps1,1-eps1]]`, default `eps1=1e-3`.
- Feature: `Phi=[[1/cphi,0],[1/cphi,eps2/cphi]]`, `cphi=sqrt(2+eps2^2)`, then normalized.

### E3

- `gamma` (all cases): `0.99`
- 3-state metastable trap (`n=3`, `d=2`, `gamma=0.99`) [renumbered from legacy E4].
- Transition: `P=[[0,1,0],[1-eps1,0,eps1],[eps1,0,1-eps1]]`, default `eps1=1e-3`.
- Feature: `Phi=[[1/cphi,0],[1/cphi,eps2/cphi],[0,0]]`, `cphi=sqrt(2+eps2^2)`, then normalized.

### E4

- `gamma` (all cases): `0.99`
- Ring chain (`n=m=20`, `d=20`, `gamma=0.99`) [renumbered from legacy E5].
- Transition: `P(i,i)=eps1`, `P(i,i+1 mod m)=1-eps1`, default `eps1=1e-2`.
- Feature: identity `I_m`, then `feature_omega_beta` on columns `j>=2`, then normalized.

### E5

- `gamma` (all cases): `0.99`
- Conveyor-reset chain (`n=m+1=21`, `d=20`, `gamma=0.99`) [renumbered from legacy E6].
- Transition: state 0 sticks/jumps to 1; states `1..m-1` deterministically advance; state `m` resets to 0.
- Feature: shifted identity (`Phi[i+1,i]=1`), then `feature_omega_beta` and normalization.

### E6

- `gamma` (all cases): `0.99`
- Ring harmonic features (`n=m=32`, `d=2`, `gamma=0.99`) [renumbered from legacy E8].
- Transition: ring form with `m=32` and default `eps1=1e-2`.
- Feature: `Phi[i,:]=[cos(2pi i/m), sin(2pi i/m)]/sqrt(m)`, then `feature_omega_beta` and normalization.

### E7

- `gamma` (all cases): `0.99`
- Excursion arc with reset hub (`n=m+1=65`, `d=2`, `gamma=0.99`) [renumbered from legacy E9].
- Transition: `0->1` deterministically; `i->i+1` with prob `1-eps1` and `i->0` with prob `eps1`; last state resets to 0.
- Feature: hub state all-zero; arc states use `[cos(alpha_i), sin(alpha_i)]/sqrt(m)`, `alpha_i=alpha_max*(i/m)`.

### E8

- `gamma` (all cases): `0.99`
- 4-cycle bow-tie features (`n=4`, `d=2`, `gamma=0.99`) [renumbered from legacy E10].
- Transition: ring with `m=4`, `eps1=1e-2`.
- Feature rows: `[1,0]`, `[1,eps2]`, `[0,1]`, `[-1,eps2]`, all scaled by `1/sqrt(3)` then normalized.

### E9

- `gamma` (all cases): `0.99`
- Reflecting corridor (`n=m+1=51`, `d=2`, `gamma=0.99`) [renumbered from legacy E11].
- Transition: endpoint self-loop 0.75 + inward move 0.25; interior `[left,stay,right]=[0.25,0.5,0.25]`.
- Feature: `Phi[i,:]=[1/cphi, eps2*(2i-m)/(m*cphi)]`, `cphi=sqrt((m+1)(1+eps2^2))`, then normalized.

### E10

- `gamma` (all cases): `0.99`
- Two-cluster block chain (`n=2k=20`, `d=2`, `gamma=0.99`) [renumbered from legacy E12].
- Transition: intra-cluster prob `(1-eps1)` and inter-cluster prob `eps1`, both spread uniformly across destination cluster.
- Feature: first cluster `[1, +eps2]/sqrt(2k)`, second cluster `[1, -eps2]/sqrt(2k)`, then normalized.

## C. 44-Case Full Quantity Table

| instance_key | env | case | control | value | gamma | n | d | omega | kappa | lambda_min((A+A^T)/2) | phi_inf^2 | tau_proxy | best_k | delta(P^best_k) | alpha_hat | 1/(1-alpha_hat) | C_hat | t_mix_upper_alpha | theta* norm | R_oracle | R_upper |
|---|---|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| toyexample_case0001_feature_omega_beta_1em3 | toyexample | 0001 | feature_omega_beta | 1e-3 | 0.99 | 50 | 5 | 5.69771043773e-10 | 5459085.70631 | 3.78596591726e-08 | 1 | 156.614800339 | 254 | 0.249894277314 | 0.994555358987 | 183.666838212 | 1 | 2540 | 7023.19068356 | 7023.19068356 | 83651184.4495 |
| toyexample_case0002_feature_omega_beta_1em2 | toyexample | 0002 | feature_omega_beta | 1e-2 | 0.99 | 50 | 5 | 5.69725598859e-08 | 54603.9103914 | 3.78566469146e-06 | 1 | 156.614800339 | 254 | 0.249894277314 | 0.994555358987 | 183.666838212 | 1 | 2540 | 702.356100839 | 702.356100839 | 8365452.06566 |
| toyexample_case0003_feature_omega_beta_1em1 | toyexample | 0003 | feature_omega_beta | 1e-1 | 0.99 | 50 | 5 | 5.65217088486e-06 | 559.234471857 | 0.000375577839361 | 1 | 156.614800339 | 254 | 0.249894277314 | 0.994555358987 | 183.666838212 | 1 | 2540 | 70.6056937735 | 70.6056937735 | 839874.97276 |
| toyexample_case0004_feature_omega_beta_1p0 | toyexample | 0004 | feature_omega_beta | 1.0 | 0.99 | 50 | 5 | 0.00017524271656 | 23.8494127276 | 0.0117303142215 | 1 | 156.614800339 | 254 | 0.249894277314 | 0.994555358987 | 183.666838212 | 1 | 2540 | 14.06379014 | 14.06379014 | 150835.05757 |
| E1_case0001_eps2_1em4 | E1 | 0001 | eps2 | 1e-4 | 0.99 | 2 | 1 | 0.00500000005 | 1 | 0.499406103995 | 1 | 1 | 1 | 0.998 | 0.998 | 500 | 1 | 6901 | 0 | 0 | 0 |
| E1_case0002_eps2_1em2 | E1 | 0002 | eps2 | 1e-2 | 0.99 | 2 | 1 | 0.0050005 | 1 | 0.4896648505 | 1 | 1 | 1 | 0.998 | 0.998 | 500 | 1 | 6901 | 0 | 0 | 0 |
| E1_case0003_eps2_1em1 | E1 | 0003 | eps2 | 1e-1 | 0.99 | 2 | 1 | 0.00505 | 1 | 0.40559905 | 1 | 1 | 1 | 0.998 | 0.998 | 500 | 1 | 6901 | 0 | 0 | 0 |
| E1_case0004_eps2_1p0 | E1 | 0004 | eps2 | 1.0 | 0.99 | 2 | 1 | 0.01 | 1 | 0.01 | 1 | 1 | 1 | 0.998 | 0.998 | 500 | 1 | 6901 | 0 | 0 | 0 |
| E2_case0001_eps2_1em4 | E2 | 0001 | eps2 | 1e-4 | 0.99 | 2 | 2 | 2.49999996875e-11 | 400000002 | 2.99499996256e-11 | 1 | 1 | 1 | 0.998 | 0.998 | 500 | 1 | 6901 | 0 | 0 | 0 |
| E2_case0002_eps2_1em2 | E2 | 0002 | eps2 | 1e-2 | 0.99 | 2 | 2 | 2.49968753125e-07 | 40002.000075 | 2.99462566206e-07 | 1 | 1 | 1 | 0.998 | 0.998 | 500 | 1 | 6901 | 0 | 0 | 0 |
| E2_case0003_eps2_1em1 | E2 | 0003 | eps2 | 1e-1 | 0.99 | 2 | 2 | 2.46905944462e-05 | 402.007512484 | 2.95792955247e-05 | 1 | 1 | 1 | 0.998 | 0.998 | 500 | 1 | 6901 | 0 | 0 | 0 |
| E2_case0004_eps2_1p0 | E2 | 0004 | eps2 | 1.0 | 0.99 | 2 | 2 | 0.000954915028125 | 6.85410196625 | 0.00113177278228 | 1 | 1 | 1 | 0.998 | 0.998 | 500 | 1 | 6901 | 0 | 0 | 0 |
| E3_case0001_eps2_1em4 | E3 | 0001 | eps2 | 1e-4 | 0.99 | 3 | 2 | 2.49999996875e-11 | 400000002 | 3.31584162522e-09 | 1 | 1 | 2 | 0.999 | 0.999499874937 | 1999.49987494 | 1 | 27618 | 0 | 0 | 0 |
| E3_case0002_eps2_1em2 | E3 | 0002 | eps2 | 1e-2 | 0.99 | 3 | 2 | 2.49968753125e-07 | 40002.000075 | 3.31542683531e-05 | 1 | 1 | 2 | 0.999 | 0.999499874937 | 1999.49987494 | 1 | 27618 | 0 | 0 | 0 |
| E3_case0003_eps2_1em1 | E3 | 0003 | eps2 | 1e-1 | 0.99 | 3 | 2 | 2.46905944462e-05 | 402.007512484 | 0.00326754941515 | 1 | 1 | 2 | 0.999 | 0.999499874937 | 1999.49987494 | 1 | 27618 | 0 | 0 | 0 |
| E3_case0004_eps2_1p0 | E3 | 0004 | eps2 | 1.0 | 0.99 | 3 | 2 | 0.000954915028125 | 6.85410196625 | 0.00347958439815 | 1 | 1 | 2 | 0.999 | 0.999499874937 | 1999.49987494 | 1 | 27618 | 0 | 0 | 0 |
| E4_case0001_feature_omega_beta_1p0 | E4 | 0001 | feature_omega_beta | 1.0 | 0.99 | 20 | 20 | 1.66666664583e-11 | 400000002 | 0.0005 | 1 | 160799772467 | 256 | 1 | 1 | 5.74003300672e+14 | 1 | 7.93005034325e+15 | 0 | 0 | 0 |
| E4_case0002_feature_omega_beta_1p0 | E4 | 0002 | feature_omega_beta | 1.0 | 0.99 | 20 | 20 | 1.66645835416e-07 | 40002.000075 | 0.0005 | 1 | 160799772467 | 256 | 1 | 1 | 5.74003300672e+14 | 1 | 7.93005034325e+15 | 0 | 0 | 0 |
| E4_case0003_feature_omega_beta_1p0 | E4 | 0003 | feature_omega_beta | 1.0 | 0.99 | 20 | 20 | 1.64603962974e-05 | 402.007512484 | 0.0005 | 1 | 160799772467 | 256 | 1 | 1 | 5.74003300672e+14 | 1 | 7.93005034325e+15 | 0 | 0 | 0 |
| E4_case0004_feature_omega_beta_1p0 | E4 | 0004 | feature_omega_beta | 1.0 | 0.99 | 20 | 20 | 0.00063661001875 | 6.85410196625 | 0.0005 | 1 | 160799772467 | 256 | 1 | 1 | 5.74003300672e+14 | 1 | 7.93005034325e+15 | 0 | 0 | 0 |
| E5_case0001_feature_omega_beta_1em3 | E5 | 0001 | feature_omega_beta | 1e-3 | 0.99 | 21 | 20 | 5e-10 | 1000000 | 1.75838076879e-10 | 1 | 2063.31047213 | 101 | 7.3048759539e-07 | 0.869448157626 | 7.65979232323 | 1 | 101 | 0 | 0 | 0 |
| E5_case0002_feature_omega_beta_1em2 | E5 | 0002 | feature_omega_beta | 1e-2 | 0.99 | 21 | 20 | 5e-08 | 10000 | 1.75836963995e-08 | 1 | 2063.31047213 | 101 | 7.3048759539e-07 | 0.869448157626 | 7.65979232323 | 1 | 101 | 0 | 0 | 0 |
| E5_case0003_feature_omega_beta_1em1 | E5 | 0003 | feature_omega_beta | 1e-1 | 0.99 | 21 | 20 | 5e-06 | 100 | 1.75833545602e-06 | 1 | 2063.31047213 | 101 | 7.3048759539e-07 | 0.869448157626 | 7.65979232323 | 1 | 101 | 0 | 0 | 0 |
| E5_case0004_feature_omega_beta_1p0 | E5 | 0004 | feature_omega_beta | 1.0 | 0.99 | 21 | 20 | 0.0005 | 1 | 0.000175479016976 | 1 | 2063.31047213 | 101 | 7.3048759539e-07 | 0.869448157626 | 7.65979232323 | 1 | 101 | 0 | 0 | 0 |
| E6_case0001_feature_omega_beta_1em3 | E6 | 0001 | feature_omega_beta | 1e-3 | 0.99 | 20 | 2 | 8.33333333333e-11 | 1000000 | 2.89847541896e-08 | 1 | inf | 256 | 0.999396187622 | 0.999997640648 | 423845.246133 | 1 | 5855744 | 0 | 0 | 0 |
| E6_case0002_feature_omega_beta_1em2 | E6 | 0002 | feature_omega_beta | 1e-2 | 0.99 | 20 | 2 | 8.33333333333e-09 | 10000 | 2.89847541896e-06 | 1 | inf | 256 | 0.999396187622 | 0.999997640648 | 423845.246133 | 1 | 5855744 | 0 | 0 | 0 |
| E6_case0003_feature_omega_beta_1em1 | E6 | 0003 | feature_omega_beta | 1e-1 | 0.99 | 20 | 2 | 8.33333333333e-07 | 100 | 0.000289847541896 | 1 | inf | 256 | 0.999396187622 | 0.999997640648 | 423845.246133 | 1 | 5855744 | 0 | 0 | 0 |
| E6_case0004_feature_omega_beta_1p0 | E6 | 0004 | feature_omega_beta | 1.0 | 0.99 | 20 | 2 | 8.33333333333e-05 | 1 | 0.0289847541896 | 1 | inf | 256 | 0.999396187622 | 0.999997640648 | 423845.246133 | 1 | 5855744 | 0 | 0 | 0 |
| E7_case0001_feature_omega_beta_1p0 | E7 | 0001 | feature_omega_beta | 1.0 | 0.99 | 65 | 2 | 0.00500000005 | 1 | 0.00952379947973 | 1 | 1 | 64 | 0.939854673172 | 0.999031250499 | 1032.25859646 | 1 | 14272 | 90.9843498546 | 90.9843498546 | 28284.271106 |
| E7_case0002_feature_omega_beta_1p0 | E7 | 0002 | feature_omega_beta | 1.0 | 0.99 | 65 | 2 | 0.0050005 | 1 | 0.00952379947973 | 1 | 1 | 64 | 0.939854673172 | 0.999031250499 | 1032.25859646 | 1 | 14272 | 90.2354406712 | 90.2354406712 | 28282.85714 |
| E7_case0003_feature_omega_beta_1p0 | E7 | 0003 | feature_omega_beta | 1.0 | 0.99 | 65 | 2 | 0.00505 | 1 | 0.00952379947973 | 1 | 1 | 64 | 0.939854673172 | 0.999031250499 | 1032.25859646 | 1 | 14272 | 82.55441712 | 82.55441712 | 28143.9017892 |
| E7_case0004_feature_omega_beta_1p0 | E7 | 0004 | feature_omega_beta | 1.0 | 0.99 | 65 | 2 | 0.01 | 1 | 0.00952379947973 | 1 | 1 | 64 | 0.939854673172 | 0.999031250499 | 1032.25859646 | 1 | 14272 | 0 | 0 | 20000 |
| E8_case0001_eps2_1em2 | E8 | 0001 | eps2 | 1e-2 | 0.99 | 4 | 2 | 5e-09 | 1000000 | 2.42665919965e-07 | 1 | 5250.67467906 | 155 | 0.213369692413 | 0.990083502578 | 100.842057177 | 1 | 1395 | 0 | 0 | 0 |
| E8_case0002_eps2_1em2 | E8 | 0002 | eps2 | 1e-2 | 0.99 | 4 | 2 | 5e-07 | 10000 | 2.42665917301e-05 | 1 | 5250.67467906 | 155 | 0.213369692413 | 0.990083502578 | 100.842057177 | 1 | 1395 | 0 | 0 | 0 |
| E8_case0003_eps2_1em2 | E8 | 0003 | eps2 | 1e-2 | 0.99 | 4 | 2 | 5e-05 | 100 | 0.00242665650818 | 1 | 5250.67467906 | 155 | 0.213369692413 | 0.990083502578 | 100.842057177 | 1 | 1395 | 0 | 0 | 0 |
| E8_case0004_eps2_1em2 | E8 | 0004 | eps2 | 1e-2 | 0.99 | 4 | 2 | 0.005 | 1 | 0.242637731687 | 1 | 5250.67467906 | 155 | 0.213369692413 | 0.990083502578 | 100.842057177 | 1 | 1395 | 0 | 0 | 0 |
| E9_case0001_eps2_1em2 | E9 | 0001 | eps2 | 1e-2 | 0.99 | 65 | 2 | 2.56833816894e-09 | 2124886.77539 | 3.67548076886e-13 | 1 | inf | 256 | 0.991800996578 | 0.999967841142 | 31095.6312536 | 1 | 429824 | 0 | 0 | 0 |
| E9_case0002_eps2_1em2 | E9 | 0002 | eps2 | 1e-2 | 0.99 | 65 | 2 | 2.56825537661e-07 | 21250.2352313 | 3.67548073248e-11 | 1 | inf | 256 | 0.991800996578 | 0.999967841142 | 31095.6312536 | 1 | 429824 | 0 | 0 | 0 |
| E9_case0003_eps2_1em2 | E9 | 0003 | eps2 | 1e-2 | 0.99 | 65 | 2 | 2.55996427261e-05 | 213.878516585 | 3.67547709375e-09 | 1 | inf | 256 | 0.991800996578 | 0.999967841142 | 31095.6312536 | 1 | 429824 | 0 | 0 | 0 |
| E9_case0004_eps2_1em2 | E9 | 0004 | eps2 | 1e-2 | 0.99 | 65 | 2 | 0.00173785398504 | 4.63543348483 | 3.6751132579e-07 | 1 | inf | 256 | 0.991800996578 | 0.999967841142 | 31095.6312536 | 1 | 429824 | 0 | 0 | 0 |
| E10_case0001_eps2_1em4 | E10 | 0001 | eps2 | 1e-4 | 0.99 | 20 | 2 | 0.002500000025 | 2.99999994 | 2.9799999702e-10 | 1 | 1 | 1 | 0.98 | 0.98 | 50 | 1 | 684 | 0 | 0 | 0 |
| E10_case0002_eps2_1em2 | E10 | 0002 | eps2 | 1e-2 | 0.99 | 20 | 2 | 0.002500249975 | 2.99940011998 | 2.9797020298e-06 | 1 | 1 | 1 | 0.98 | 0.98 | 50 | 1 | 684 | 0 | 0 | 0 |
| E10_case0003_eps2_1em1 | E10 | 0003 | eps2 | 1e-1 | 0.99 | 20 | 2 | 0.00252475247525 | 2.94117647059 | 0.00029504950495 | 1 | 1 | 1 | 0.98 | 0.98 | 50 | 1 | 684 | 0 | 0 | 0 |
| E10_case0004_eps2_1p0 | E10 | 0004 | eps2 | 1.0 | 0.99 | 20 | 2 | 0.00375 | 1 | 0.005 | 1 | 1 | 1 | 0.98 | 0.98 | 50 | 1 | 684 | 0 | 0 | 0 |

## D. Per-Environment Matrix Dumps (P, D, Phi)

每個 case 的完整矩陣檔都已輸出到 `matrix_dir`：`P.tsv`, `D.tsv`, `Phi.tsv`。
同一 env 的 4 個 case 只改 feature-sweep 參數時，`P` 與 `D` 相同；`Phi` 隨 sweep 改變。

### toyexample

- Full D vector (shared transition for this env): [0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02, 0.02]
- D length: 50

| case | control | value | omega | kappa | lambda_min((A+A^T)/2) | tau_proxy | best_k | alpha_hat | 1/(1-alpha_hat) | t_mix_upper_alpha | P.tsv | D.tsv | Phi.tsv |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|---|
| 0001 | feature_omega_beta | 1e-3 | 5.69771043773e-10 | 5459085.70631 | 3.78596591726e-08 | 156.614800339 | 254 | 0.994555358987 | 183.666838212 | 2540 | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/toyexample_case0001_feature_omega_beta_1em3/P.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/toyexample_case0001_feature_omega_beta_1em3/D.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/toyexample_case0001_feature_omega_beta_1em3/Phi.tsv |
| 0002 | feature_omega_beta | 1e-2 | 5.69725598859e-08 | 54603.9103914 | 3.78566469146e-06 | 156.614800339 | 254 | 0.994555358987 | 183.666838212 | 2540 | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/toyexample_case0002_feature_omega_beta_1em2/P.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/toyexample_case0002_feature_omega_beta_1em2/D.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/toyexample_case0002_feature_omega_beta_1em2/Phi.tsv |
| 0003 | feature_omega_beta | 1e-1 | 5.65217088486e-06 | 559.234471857 | 0.000375577839361 | 156.614800339 | 254 | 0.994555358987 | 183.666838212 | 2540 | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/toyexample_case0003_feature_omega_beta_1em1/P.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/toyexample_case0003_feature_omega_beta_1em1/D.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/toyexample_case0003_feature_omega_beta_1em1/Phi.tsv |
| 0004 | feature_omega_beta | 1.0 | 0.00017524271656 | 23.8494127276 | 0.0117303142215 | 156.614800339 | 254 | 0.994555358987 | 183.666838212 | 2540 | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/toyexample_case0004_feature_omega_beta_1p0/P.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/toyexample_case0004_feature_omega_beta_1p0/D.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/toyexample_case0004_feature_omega_beta_1p0/Phi.tsv |

### E1

- Full D vector (shared transition for this env): [0.5, 0.5]
- D length: 2

| case | control | value | omega | kappa | lambda_min((A+A^T)/2) | tau_proxy | best_k | alpha_hat | 1/(1-alpha_hat) | t_mix_upper_alpha | P.tsv | D.tsv | Phi.tsv |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|---|
| 0001 | eps2 | 1e-4 | 0.00500000005 | 1 | 0.499406103995 | 1 | 1 | 0.998 | 500 | 6901 | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E1_case0001_eps2_1em4/P.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E1_case0001_eps2_1em4/D.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E1_case0001_eps2_1em4/Phi.tsv |
| 0002 | eps2 | 1e-2 | 0.0050005 | 1 | 0.4896648505 | 1 | 1 | 0.998 | 500 | 6901 | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E1_case0002_eps2_1em2/P.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E1_case0002_eps2_1em2/D.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E1_case0002_eps2_1em2/Phi.tsv |
| 0003 | eps2 | 1e-1 | 0.00505 | 1 | 0.40559905 | 1 | 1 | 0.998 | 500 | 6901 | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E1_case0003_eps2_1em1/P.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E1_case0003_eps2_1em1/D.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E1_case0003_eps2_1em1/Phi.tsv |
| 0004 | eps2 | 1.0 | 0.01 | 1 | 0.01 | 1 | 1 | 0.998 | 500 | 6901 | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E1_case0004_eps2_1p0/P.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E1_case0004_eps2_1p0/D.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E1_case0004_eps2_1p0/Phi.tsv |

### E2

- Full D vector (shared transition for this env): [0.5, 0.5]
- D length: 2

| case | control | value | omega | kappa | lambda_min((A+A^T)/2) | tau_proxy | best_k | alpha_hat | 1/(1-alpha_hat) | t_mix_upper_alpha | P.tsv | D.tsv | Phi.tsv |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|---|
| 0001 | eps2 | 1e-4 | 2.49999996875e-11 | 400000002 | 2.99499996256e-11 | 1 | 1 | 0.998 | 500 | 6901 | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E2_case0001_eps2_1em4/P.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E2_case0001_eps2_1em4/D.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E2_case0001_eps2_1em4/Phi.tsv |
| 0002 | eps2 | 1e-2 | 2.49968753125e-07 | 40002.000075 | 2.99462566206e-07 | 1 | 1 | 0.998 | 500 | 6901 | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E2_case0002_eps2_1em2/P.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E2_case0002_eps2_1em2/D.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E2_case0002_eps2_1em2/Phi.tsv |
| 0003 | eps2 | 1e-1 | 2.46905944462e-05 | 402.007512484 | 2.95792955247e-05 | 1 | 1 | 0.998 | 500 | 6901 | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E2_case0003_eps2_1em1/P.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E2_case0003_eps2_1em1/D.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E2_case0003_eps2_1em1/Phi.tsv |
| 0004 | eps2 | 1.0 | 0.000954915028125 | 6.85410196625 | 0.00113177278228 | 1 | 1 | 0.998 | 500 | 6901 | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E2_case0004_eps2_1p0/P.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E2_case0004_eps2_1p0/D.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E2_case0004_eps2_1p0/Phi.tsv |

### E3

- Full D vector (shared transition for this env): [0.33333333, 0.33333333, 0.33333333]
- D length: 3

| case | control | value | omega | kappa | lambda_min((A+A^T)/2) | tau_proxy | best_k | alpha_hat | 1/(1-alpha_hat) | t_mix_upper_alpha | P.tsv | D.tsv | Phi.tsv |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|---|
| 0001 | eps2 | 1e-4 | 2.49999996875e-11 | 400000002 | 3.31584162522e-09 | 1 | 2 | 0.999499874937 | 1999.49987494 | 27618 | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E3_case0001_eps2_1em4/P.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E3_case0001_eps2_1em4/D.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E3_case0001_eps2_1em4/Phi.tsv |
| 0002 | eps2 | 1e-2 | 2.49968753125e-07 | 40002.000075 | 3.31542683531e-05 | 1 | 2 | 0.999499874937 | 1999.49987494 | 27618 | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E3_case0002_eps2_1em2/P.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E3_case0002_eps2_1em2/D.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E3_case0002_eps2_1em2/Phi.tsv |
| 0003 | eps2 | 1e-1 | 2.46905944462e-05 | 402.007512484 | 0.00326754941515 | 1 | 2 | 0.999499874937 | 1999.49987494 | 27618 | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E3_case0003_eps2_1em1/P.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E3_case0003_eps2_1em1/D.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E3_case0003_eps2_1em1/Phi.tsv |
| 0004 | eps2 | 1.0 | 0.000954915028125 | 6.85410196625 | 0.00347958439815 | 1 | 2 | 0.999499874937 | 1999.49987494 | 27618 | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E3_case0004_eps2_1p0/P.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E3_case0004_eps2_1p0/D.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E3_case0004_eps2_1p0/Phi.tsv |

### E4

- Full D vector (shared transition for this env): [0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05]
- D length: 20

| case | control | value | omega | kappa | lambda_min((A+A^T)/2) | tau_proxy | best_k | alpha_hat | 1/(1-alpha_hat) | t_mix_upper_alpha | P.tsv | D.tsv | Phi.tsv |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|---|
| 0001 | feature_omega_beta | 1.0 | 1.66666664583e-11 | 400000002 | 0.0005 | 160799772467 | 256 | 1 | 5.74003300672e+14 | 7.93005034325e+15 | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E4_case0001_feature_omega_beta_1p0/P.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E4_case0001_feature_omega_beta_1p0/D.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E4_case0001_feature_omega_beta_1p0/Phi.tsv |
| 0002 | feature_omega_beta | 1.0 | 1.66645835416e-07 | 40002.000075 | 0.0005 | 160799772467 | 256 | 1 | 5.74003300672e+14 | 7.93005034325e+15 | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E4_case0002_feature_omega_beta_1p0/P.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E4_case0002_feature_omega_beta_1p0/D.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E4_case0002_feature_omega_beta_1p0/Phi.tsv |
| 0003 | feature_omega_beta | 1.0 | 1.64603962974e-05 | 402.007512484 | 0.0005 | 160799772467 | 256 | 1 | 5.74003300672e+14 | 7.93005034325e+15 | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E4_case0003_feature_omega_beta_1p0/P.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E4_case0003_feature_omega_beta_1p0/D.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E4_case0003_feature_omega_beta_1p0/Phi.tsv |
| 0004 | feature_omega_beta | 1.0 | 0.00063661001875 | 6.85410196625 | 0.0005 | 160799772467 | 256 | 1 | 5.74003300672e+14 | 7.93005034325e+15 | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E4_case0004_feature_omega_beta_1p0/P.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E4_case0004_feature_omega_beta_1p0/D.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E4_case0004_feature_omega_beta_1p0/Phi.tsv |

### E5

- Full D vector (shared transition for this env): [0.83333333, 0.0083333333, 0.0083333333, 0.0083333333, 0.0083333333, 0.0083333333, 0.0083333333, 0.0083333333, 0.0083333333, 0.0083333333, 0.0083333333, 0.0083333333, 0.0083333333, 0.0083333333, 0.0083333333, 0.0083333333, 0.0083333333, 0.0083333333, 0.0083333333, 0.0083333333, 0.0083333333]
- D length: 21

| case | control | value | omega | kappa | lambda_min((A+A^T)/2) | tau_proxy | best_k | alpha_hat | 1/(1-alpha_hat) | t_mix_upper_alpha | P.tsv | D.tsv | Phi.tsv |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|---|
| 0001 | feature_omega_beta | 1e-3 | 5e-10 | 1000000 | 1.75838076879e-10 | 2063.31047213 | 101 | 0.869448157626 | 7.65979232323 | 101 | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E5_case0001_feature_omega_beta_1em3/P.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E5_case0001_feature_omega_beta_1em3/D.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E5_case0001_feature_omega_beta_1em3/Phi.tsv |
| 0002 | feature_omega_beta | 1e-2 | 5e-08 | 10000 | 1.75836963995e-08 | 2063.31047213 | 101 | 0.869448157626 | 7.65979232323 | 101 | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E5_case0002_feature_omega_beta_1em2/P.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E5_case0002_feature_omega_beta_1em2/D.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E5_case0002_feature_omega_beta_1em2/Phi.tsv |
| 0003 | feature_omega_beta | 1e-1 | 5e-06 | 100 | 1.75833545602e-06 | 2063.31047213 | 101 | 0.869448157626 | 7.65979232323 | 101 | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E5_case0003_feature_omega_beta_1em1/P.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E5_case0003_feature_omega_beta_1em1/D.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E5_case0003_feature_omega_beta_1em1/Phi.tsv |
| 0004 | feature_omega_beta | 1.0 | 0.0005 | 1 | 0.000175479016976 | 2063.31047213 | 101 | 0.869448157626 | 7.65979232323 | 101 | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E5_case0004_feature_omega_beta_1p0/P.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E5_case0004_feature_omega_beta_1p0/D.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E5_case0004_feature_omega_beta_1p0/Phi.tsv |

### E6

- Full D vector (shared transition for this env): [0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05]
- D length: 20

| case | control | value | omega | kappa | lambda_min((A+A^T)/2) | tau_proxy | best_k | alpha_hat | 1/(1-alpha_hat) | t_mix_upper_alpha | P.tsv | D.tsv | Phi.tsv |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|---|
| 0001 | feature_omega_beta | 1e-3 | 8.33333333333e-11 | 1000000 | 2.89847541896e-08 | inf | 256 | 0.999997640648 | 423845.246133 | 5855744 | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E6_case0001_feature_omega_beta_1em3/P.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E6_case0001_feature_omega_beta_1em3/D.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E6_case0001_feature_omega_beta_1em3/Phi.tsv |
| 0002 | feature_omega_beta | 1e-2 | 8.33333333333e-09 | 10000 | 2.89847541896e-06 | inf | 256 | 0.999997640648 | 423845.246133 | 5855744 | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E6_case0002_feature_omega_beta_1em2/P.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E6_case0002_feature_omega_beta_1em2/D.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E6_case0002_feature_omega_beta_1em2/Phi.tsv |
| 0003 | feature_omega_beta | 1e-1 | 8.33333333333e-07 | 100 | 0.000289847541896 | inf | 256 | 0.999997640648 | 423845.246133 | 5855744 | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E6_case0003_feature_omega_beta_1em1/P.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E6_case0003_feature_omega_beta_1em1/D.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E6_case0003_feature_omega_beta_1em1/Phi.tsv |
| 0004 | feature_omega_beta | 1.0 | 8.33333333333e-05 | 1 | 0.0289847541896 | inf | 256 | 0.999997640648 | 423845.246133 | 5855744 | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E6_case0004_feature_omega_beta_1p0/P.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E6_case0004_feature_omega_beta_1p0/D.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E6_case0004_feature_omega_beta_1p0/Phi.tsv |

### E7

- Full D vector (shared transition for this env): [0.01586671, 0.01586671, 0.015850844, 0.015834993, 0.015819158, 0.015803339, 0.015787535, 0.015771748, 0.015755976, 0.01574022, 0.01572448, 0.015708755, 0.015693047, 0.015677354, 0.015661676, 0.015646015, 0.015630369, 0.015614738, 0.015599123, 0.015583524, 0.015567941, 0.015552373, 0.015536821, 0.015521284, 0.015505762, 0.015490257, 0.015474766, 0.015459292, 0.015443832, 0.015428389, 0.01541296, 0.015397547, 0.01538215, 0.015366767, 0.015351401, 0.015336049, 0.015320713, 0.015305393, 0.015290087, 0.015274797, 0.015259522, 0.015244263, 0.015229018, 0.015213789, 0.015198576, 0.015183377, 0.015168194, 0.015153026, 0.015137872, 0.015122735, 0.015107612, 0.015092504, 0.015077412, 0.015062334, 0.015047272, 0.015032225, 0.015017193, 0.015002175, 0.014987173, 0.014972186, 0.014957214, 0.014942257, 0.014927314, 0.014912387, 0.014897475]
- D length: 65

| case | control | value | omega | kappa | lambda_min((A+A^T)/2) | tau_proxy | best_k | alpha_hat | 1/(1-alpha_hat) | t_mix_upper_alpha | P.tsv | D.tsv | Phi.tsv |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|---|
| 0001 | feature_omega_beta | 1.0 | 0.00500000005 | 1 | 0.00952379947973 | 1 | 64 | 0.999031250499 | 1032.25859646 | 14272 | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E7_case0001_feature_omega_beta_1p0/P.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E7_case0001_feature_omega_beta_1p0/D.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E7_case0001_feature_omega_beta_1p0/Phi.tsv |
| 0002 | feature_omega_beta | 1.0 | 0.0050005 | 1 | 0.00952379947973 | 1 | 64 | 0.999031250499 | 1032.25859646 | 14272 | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E7_case0002_feature_omega_beta_1p0/P.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E7_case0002_feature_omega_beta_1p0/D.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E7_case0002_feature_omega_beta_1p0/Phi.tsv |
| 0003 | feature_omega_beta | 1.0 | 0.00505 | 1 | 0.00952379947973 | 1 | 64 | 0.999031250499 | 1032.25859646 | 14272 | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E7_case0003_feature_omega_beta_1p0/P.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E7_case0003_feature_omega_beta_1p0/D.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E7_case0003_feature_omega_beta_1p0/Phi.tsv |
| 0004 | feature_omega_beta | 1.0 | 0.01 | 1 | 0.00952379947973 | 1 | 64 | 0.999031250499 | 1032.25859646 | 14272 | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E7_case0004_feature_omega_beta_1p0/P.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E7_case0004_feature_omega_beta_1p0/D.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E7_case0004_feature_omega_beta_1p0/Phi.tsv |

### E8

- Full D vector (shared transition for this env): [0.25, 0.25, 0.25, 0.25]
- D length: 4

| case | control | value | omega | kappa | lambda_min((A+A^T)/2) | tau_proxy | best_k | alpha_hat | 1/(1-alpha_hat) | t_mix_upper_alpha | P.tsv | D.tsv | Phi.tsv |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|---|
| 0001 | eps2 | 1e-2 | 5e-09 | 1000000 | 2.42665919965e-07 | 5250.67467906 | 155 | 0.990083502578 | 100.842057177 | 1395 | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E8_case0001_eps2_1em2/P.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E8_case0001_eps2_1em2/D.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E8_case0001_eps2_1em2/Phi.tsv |
| 0002 | eps2 | 1e-2 | 5e-07 | 10000 | 2.42665917301e-05 | 5250.67467906 | 155 | 0.990083502578 | 100.842057177 | 1395 | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E8_case0002_eps2_1em2/P.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E8_case0002_eps2_1em2/D.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E8_case0002_eps2_1em2/Phi.tsv |
| 0003 | eps2 | 1e-2 | 5e-05 | 100 | 0.00242665650818 | 5250.67467906 | 155 | 0.990083502578 | 100.842057177 | 1395 | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E8_case0003_eps2_1em2/P.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E8_case0003_eps2_1em2/D.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E8_case0003_eps2_1em2/Phi.tsv |
| 0004 | eps2 | 1e-2 | 0.005 | 1 | 0.242637731687 | 5250.67467906 | 155 | 0.990083502578 | 100.842057177 | 1395 | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E8_case0004_eps2_1em2/P.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E8_case0004_eps2_1em2/D.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E8_case0004_eps2_1em2/Phi.tsv |

### E9

- Full D vector (shared transition for this env): [0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615, 0.015384615]
- D length: 65

| case | control | value | omega | kappa | lambda_min((A+A^T)/2) | tau_proxy | best_k | alpha_hat | 1/(1-alpha_hat) | t_mix_upper_alpha | P.tsv | D.tsv | Phi.tsv |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|---|
| 0001 | eps2 | 1e-2 | 2.56833816894e-09 | 2124886.77539 | 3.67548076886e-13 | inf | 256 | 0.999967841142 | 31095.6312536 | 429824 | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E9_case0001_eps2_1em2/P.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E9_case0001_eps2_1em2/D.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E9_case0001_eps2_1em2/Phi.tsv |
| 0002 | eps2 | 1e-2 | 2.56825537661e-07 | 21250.2352313 | 3.67548073248e-11 | inf | 256 | 0.999967841142 | 31095.6312536 | 429824 | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E9_case0002_eps2_1em2/P.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E9_case0002_eps2_1em2/D.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E9_case0002_eps2_1em2/Phi.tsv |
| 0003 | eps2 | 1e-2 | 2.55996427261e-05 | 213.878516585 | 3.67547709375e-09 | inf | 256 | 0.999967841142 | 31095.6312536 | 429824 | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E9_case0003_eps2_1em2/P.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E9_case0003_eps2_1em2/D.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E9_case0003_eps2_1em2/Phi.tsv |
| 0004 | eps2 | 1e-2 | 0.00173785398504 | 4.63543348483 | 3.6751132579e-07 | inf | 256 | 0.999967841142 | 31095.6312536 | 429824 | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E9_case0004_eps2_1em2/P.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E9_case0004_eps2_1em2/D.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E9_case0004_eps2_1em2/Phi.tsv |

### E10

- Full D vector (shared transition for this env): [0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05, 0.05]
- D length: 20

| case | control | value | omega | kappa | lambda_min((A+A^T)/2) | tau_proxy | best_k | alpha_hat | 1/(1-alpha_hat) | t_mix_upper_alpha | P.tsv | D.tsv | Phi.tsv |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|---|
| 0001 | eps2 | 1e-4 | 0.002500000025 | 2.99999994 | 2.9799999702e-10 | 1 | 1 | 0.98 | 50 | 684 | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E10_case0001_eps2_1em4/P.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E10_case0001_eps2_1em4/D.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E10_case0001_eps2_1em4/Phi.tsv |
| 0002 | eps2 | 1e-2 | 0.002500249975 | 2.99940011998 | 2.9797020298e-06 | 1 | 1 | 0.98 | 50 | 684 | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E10_case0002_eps2_1em2/P.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E10_case0002_eps2_1em2/D.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E10_case0002_eps2_1em2/Phi.tsv |
| 0003 | eps2 | 1e-1 | 0.00252475247525 | 2.94117647059 | 0.00029504950495 | 1 | 1 | 0.98 | 50 | 684 | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E10_case0003_eps2_1em1/P.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E10_case0003_eps2_1em1/D.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E10_case0003_eps2_1em1/Phi.tsv |
| 0004 | eps2 | 1.0 | 0.00375 | 1 | 0.005 | 1 | 1 | 0.98 | 50 | 684 | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E10_case0004_eps2_1p0/P.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E10_case0004_eps2_1p0/D.tsv | /home/leew0a/codex/TDfullexperiments/verification/instance_matrices_20260404/E10_case0004_eps2_1p0/Phi.tsv |

## E. Redundancy Analysis for Hard-Instance Challenge

### E.1 Strict duplicate groups (same omega/kappa/tau_proxy up to numerical tolerance)

- group size 2: E1(case0001, eps2=1e-4) ; E7(case0001, feature_omega_beta=1.0)
- group size 2: E1(case0002, eps2=1e-2) ; E7(case0002, feature_omega_beta=1.0)
- group size 2: E1(case0003, eps2=1e-1) ; E7(case0003, feature_omega_beta=1.0)
- group size 2: E1(case0004, eps2=1.0) ; E7(case0004, feature_omega_beta=1.0)
- group size 2: E2(case0001, eps2=1e-4) ; E3(case0001, eps2=1e-4)
- group size 2: E2(case0002, eps2=1e-2) ; E3(case0002, eps2=1e-2)
- group size 2: E2(case0003, eps2=1e-1) ; E3(case0003, eps2=1e-1)
- group size 2: E2(case0004, eps2=1.0) ; E3(case0004, eps2=1.0)

### E.2 Repeated hardness bins

- Bin signature: `(floor(log10(omega)), tau_regime)`.
- `tau_regime`: `fast<=1e1`, `mid<=1e3`, `slow<=1e6`, `vslow>1e6`, `inf`.

| omega_decade | tau_regime | count | members |
|---:|---|---:|---|
| -11 | fast<=1e1 | 2 | E2:case0001, E3:case0001 |
| -9 | inf | 2 | E6:case0002, E9:case0001 |
| -7 | fast<=1e1 | 2 | E2:case0002, E3:case0002 |
| -7 | inf | 2 | E6:case0003, E9:case0002 |
| -5 | fast<=1e1 | 2 | E2:case0003, E3:case0003 |
| -5 | inf | 2 | E6:case0004, E9:case0003 |
| -4 | fast<=1e1 | 2 | E2:case0004, E3:case0004 |
| -3 | fast<=1e1 | 10 | E1:case0001, E1:case0002, E1:case0003, E7:case0001, E7:case0002, E7:case0003, E10:case0001, E10:case0002, E10:case0003, E10:case0004 |
| -2 | fast<=1e1 | 2 | E1:case0004, E7:case0004 |

### E.3 Suggested pruning policy

- Conservative dedup only: `44 -> 36`.
- Immediate safe drops: duplicate groups listed in E.1.
- Aggressive pruning rule: keep one representative per repeated hardness bin in E.2, while preserving distinct transition topology classes (`ring`, `conveyor`, `hub-reset`, `block-cluster`, `metastable-3state`).

## F. Plot Plan (v2 pipeline)

### F.1 Inputs and logged columns used by `scripts/plot_suite_v2.py`

- `manifest.tsv`: case metadata + file pointers (`agg_file`, `run_file`, `schedule`, `projection`, `param_value`, `omega`, `tau_proxy`, `kappa`, `gamma`).
- `agg_*.csv` columns used:
  - `timestep`
  - `E_D[||Vbar_t - V*||^2]`
  - `E_A[||Vbar_t - V*||^2]`
  - `max_i<=T ||theta_i||^2`
  - `||theta^*||^2`
- `runs_*.csv` columns used:
  - `diverged` (for divergence rate)

### F.2 Figure families from `scripts/plot_suite_v2.py`

1. `bestcurves_by_c (metric D)`
- Output: `{env}__bestcurves_by_c__metric-D__omega-grid-{rows}x{cols}.png`
- One subplot per omega/case; each line is a method `(schedule, projection)` at its best `c` under final `D`.
- x=`timestep` (log), y=`suboptimality D` (log).

2. `bestcurves_by_c (metric D+A)`
- Output: `{env}__bestcurves_by_c__metric-DA__omega-grid-{rows}x{cols}.png`
- Same as #1 but best-`c` selection and y-axis use final `D+A`.

3. `algo-finalgrid per method`
- Output: `{env}__algo-finalgrid__method-{method_id}__rows-omega__cols-ratio-div-D-DA.png`
- One figure per method.
- Layout: rows=omega/case, cols=[ratio, divergence, final D, final D+A], x=`c` (log).

4. `algo-curves-by-c (metric D)`
- Output: `{env}__algo-curves-by-c__metric-D__method-{method_id}__omega-grid-{rows}x{cols}.png`
- One figure per method; one subplot per omega/case; one curve per `c`.
- x=`timestep` (log), y=`suboptimality D` (log).

5. `algo-curves-by-c (metric D+A)`
- Output: `{env}__algo-curves-by-c__metric-DA__method-{method_id}__omega-grid-{rows}x{cols}.png`
- Same as #4 but y is `suboptimality D+A`.

6. `omega-method-bestc overlay (metric D)`
- Output: `{env}__omega-{idx}-{omega}__methods-bestc__metric-D.png`
- One figure per omega/case; each line is one method at its best `c` under `D`.

7. `omega-method-bestc overlay (metric D+A)`
- Output: `{env}__omega-{idx}-{omega}__methods-bestc__metric-DA.png`
- Same as #6 but best-`c` criterion is final `D+A`.

8. `omega_final_error scatter (metric D)`
- Output: `{env}__omega_final_error_D__method-{method_id}.png`
- One figure per method: x=`omega`, y=`final D`, point color=`c`.

9. `omega_final_error scatter (metric D+A)`
- Output: `{env}__omega_final_error_DA__method-{method_id}.png`
- One figure per method: x=`omega`, y=`final D+A`, point color=`c`.

10. `plot inventory`
- Output: `plot_inventory_v2.tsv` (all generated PNG filenames for that run dir).

11. `embedded report`
- Generated by `scripts/generate_embedded_report_v2.py`.
- Embeds all PNG from each run directory and optionally `instance_structure_plots/*.png` + alpha table TSV.

### F.3 Dynamic count formulas (omega count and instance count can grow)

- Current summary has `E=11` envs and `N_case=44` cases.
- Current method count from manifest: `M=1` (`1 schedules x 1 projections`).
- Per env with `C_e` cases, v2 PNG count is:
  - `N_env = 2 + 5M + 2C_e`
  - (`2` bestcurves) + (`M` finalgrid) + (`2M` curves-by-c) + (`2C_e` methods-bestc) + (`2M` omega-final-error)
- Across all envs:
  - `N_total = sum_e (2 + 5M + 2C_e)`
  - if all envs share same case count `C`: `N_total = E * (2 + 5M + 2C)`

### F.4 Optional structure visuals

- `P_heatmap` per case: x=next-state, y=state, color=`P[s,s']`.
- `Phi_heatmap` per case: x=feature index, y=state, color=`Phi[s,j]`.
- `D_bar` per case: x=state index, y=`D[s]`.
- If all structure plots are present: `3 * N_case = 132` PNG.
