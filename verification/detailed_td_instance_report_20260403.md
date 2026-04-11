# Detailed TD Instance Report (toyexample, E1~E12)

Date: 2026-04-03  
Repository: `/home/leew0a/codex/TDfullexperiments`  
Engine: `cpp/tdx`

## 1. 報表範圍與基準設定

本報表對齊你要求的 C++ 非零 `theta*` 設定（與全量 1e9 實驗一致）：

- envs: `toyexample, E1, ..., E12`
- nonzero-reward overrides:
  - `toyexample`: `scale_factor=1.0`, `seed=114514`
  - `E1~E3`: `reward_mode=driven`, `rho=1.0`
  - `E4`: `reward_mode=signed`, `rho=1.0`
  - `E5`: `reward_mode=single-site`, `rho=1.0`
  - `E6`: `reward_mode=launch`, `rho=1.0`
  - `E7`: `reward_mode=state1-only`, `rho=1.0`
  - `E8`: `reward_mode=single-harmonic`, `rho=1.0`
  - `E9`: `reward_mode=uniform`, `rho=1.0`
  - `E10`: `reward_mode=signed-cycle`, `rho=1.0`
  - `E11`: `reward_mode=linear`, `rho=1.0`
  - `E12`: `reward_mode=cluster-opposite`, `rho=1.0`

`omega/kappa/theta*` 數值來自快速結構常數抽樣（`n_steps=10, n_runs=1`，僅為讀取 instance 常數，不做收斂結論）：

- source TSV: `verification/instance_metrics_nonzero_20260403/instance_constants.tsv`
- k-step mixing TSV: `verification/kstep_dobrushin_mixing_eps1e-6.tsv`（`K=256`, `eps=1e-6`）

---

## 2. 核心數學定義（C++ 實作）

### 2.1 TD 環境與近似空間

- 有限狀態 Markov chain，轉移矩陣 `P`，stationary distribution `D`
- 線性特徵 `Phi`，參數 `theta in R^d`
- `theta*` 由 projected Bellman linear system 解出（`safe_theta_star(A, b)`）

### 2.2 `omega` 與 `kappa`

在 `compute_objective_matrices` 中：

- `A1_diag(s) = (1-gamma) D(s)`
- `G = Phi^T diag(A1_diag) Phi = (1-gamma) Phi^T D Phi`
- `omega = lambda_min(G)`
- `kappa = lambda_max(G) / lambda_min(G)`（若 `omega <= 0` 則視為 `inf`）

### 2.3 k-step Dobrushin Mixing Estimate

本報表更新後，TD instance 的 mixing 估計採用 k-step Dobrushin contraction：

- `delta_k = delta(P^k)`
- `alpha_k = delta_k^(1/k)`
- `tau_alpha_k = 1 / (1 - alpha_k)`
- `C_k = max_{0<=r<k} delta(P^r)`
- 對 `t = qk + r`（`0<=r<k`）：
  - `delta(P^t) <= C_k * delta_k^q`
  - `sup_x ||xP^t - pi||_TV <= delta(P^t)`
- 因此（`0<delta_k<1`）可得：
  - `t_mix_upper(k, eps) = k * ceil(log(eps/C_k) / log(delta_k))`

報表使用 `eps=1e-6`，並在 `k=1..256` 中選最小上界作為 `best_k`。

### 2.4 目標函數

程式在每個 checkpoint 記錄兩個 suboptimality：

- `E_D[||Vbar_t - V*||^2]`（對應 `G`）
- `E_A[||Vbar_t - V*||^2]`（對應含 Dirichlet 項的 `A2` 結構）

也就是你關注的 `(1-gamma)||.||_D + gamma||.||_Dirichlet` 方向在程式裡分解成 D/A 兩條目標軸進行追蹤。

---

## 3. toyexample, E1~E12 的 TD instance 定義

## 3.1 結構摘要（狀態數、特徵維度）

| Env | n_states | d | 轉移/特徵結構摘要 |
|---|---:|---:|---|
| toyexample | 50 | 5 | ring-like local walk (`self,+1,-1`) + random dense features |
| E1 | 2 | 1 | alternating 2-state chain + scalar feature shear |
| E2 | 2 | 2 | sticky 2-state chain + near-collinear 2D feature |
| E3 | 2 | 2 | alternating 2-state chain + near-collinear 2D feature |
| E4 | 3 | 2 | metastable 3-state trap + degenerate 3rd-state feature |
| E5 | 20 | 20 | cycle transport + identity features |
| E6 | 21 | 20 | conveyor with reset + shifted identity features |
| E7 | 2 | 1 | sticky 2-state + equal scalar features |
| E8 | 32 | 2 | ring + harmonic (`cos/sin`) features |
| E9 | 65 | 2 | open excursion arc + harmonic arc features |
| E10 | 4 | 2 | 4-cycle bow-tie feature geometry |
| E11 | 51 | 2 | reflecting corridor + linear-slope 2D features |
| E12 | 20 | 2 | two-cluster block chain + opposite-slope cluster features |

## 3.2 每個環境的實作細節

### toyexample

- `P`: 每個 state `i` 轉移到 `i`(`0.1`), `i+1`(`0.6`), `i-1`(`0.3`)（mod 50）
- `r(s,s')`: 使用 `seed` 產生的隨機數
- `Phi(s,:)`: 隨機 feature（`10 * U[0,1)`），可用 `scale_factor` 縮放

### E1

- `P`: alternating 2-state (`[[eps1,1-eps1],[1-eps1,eps1]]`)
- `Phi`: `[eps2/cphi, 1/cphi]`, `cphi = sqrt(1+eps2^2)`
- reward: `driven` 模式下 `rewards=[0, rho]`

### E2

- `P`: sticky 2-state (`[[1-eps1,eps1],[eps1,1-eps1]]`)
- `Phi`: `[[1/cphi,0],[1/cphi,eps2/cphi]]`, `cphi = sqrt(2+eps2^2)`
- reward: `driven` -> `[0, rho]`

### E3

- `P`: alternating（同 E1）
- `Phi`: 2D shear（同 E2）
- reward: `driven` -> `[0, rho]`

### E4

- `P`:
  - `0->1` 必定
  - `1->0` 機率 `1-eps1`, `1->2` 機率 `eps1`
  - `2->0` 機率 `eps1`, `2->2` 機率 `1-eps1`
- `Phi`: 第 3 個 state 特徵為零向量
- reward: `signed` -> `[0, rho, -rho]`

### E5

- `P`: 長度 `m` 的 deterministic-forward + stay noise (`eps1`)
- `Phi`: `I_m`（identity）
- reward: `single-site` -> state `0` 為 `rho`

### E6

- `P`: state 0 以 `eps1` 發射到 conveyor，conveyor 終端回 0
- `Phi`: 對 state `1..m` 使用 shifted identity（state 0 全零）
- reward: `launch` -> state `1` 為 `rho`

### E7

- `P`: sticky 2-state
- `Phi`: `[1/sqrt(2), 1/sqrt(2)]`（兩 state 同特徵）
- reward: `state1-only` -> `[rho, 0]`

### E8

- `P`: ring transition（`m=32`）
- `Phi(i,:) = [cos(2πi/m), sin(2πi/m)] / sqrt(m)`
- reward: `single-harmonic` -> `rho*cos(2πi/m)`

### E9

- `P`: open excursion chain（`0->1`，中間 state 以 `eps1` reset 到 `0`，末端回 `0`）
- `Phi(i,:) = [cos(alpha_i), sin(alpha_i)]/sqrt(m)`, `alpha_i = alpha_max*(i+1)/m`
- reward: `uniform` -> excursion states (`1..m`) 為 `rho`

### E10

- `P`: `ring_transition_matrix(4, eps1)`
- `Phi`:
  - `[1,0]`, `[1,eps2]`, `[0,1]`, `[-1,eps2]` 再除 `sqrt(3)`
- reward: `signed-cycle` -> `[0, rho, 0, -rho]`

### E11

- `P`: reflecting corridor (`m+1` states)
- `Phi`: 常數項 + 線性斜率項，`slope(i)=eps2*(2i-m)/m`
- reward: `linear` -> `rho*(2i-m)/m`

### E12

- `P`: 兩群大小 `k` 的 block chain，群內 `1-eps1`，跨群 `eps1`
- `Phi`: 第一群 slope `+eps2`，第二群 slope `-eps2`（含共同常數項）
- reward: `cluster-opposite` -> 第一群 `+rho`，第二群 `-rho`

## 3.3 實測常數表（非零 `theta*` 設定 + k-step mixing）

| Env | omega | kappa | best_k | delta_bestk | alpha_bestk | tau_alpha_bestk | t_mix_upper(eps=1e-6) | gamma | ||theta*||_2 | r_max |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| toyexample | 0.0547860516347 | 23.8494127276 | 254 | 0.249894277314 | 0.994555358987 | 183.666838212 | 2540 | 0.99 | 0.795403255955 | 0.998371755681 |
| E1 | 0.005 | 1 | 1 | 0.998 | 0.998 | 500 | 6901 | 0.99 | 1.02115763234 | 1 |
| E2 | 1.24990625469e-07 | 40002.000075 | 1 | 0.998 | 0.998 | 500 | 6901 | 0.99 | 11805.088567 | 1 |
| E3 | 1.24990625469e-07 | 40002.000075 | 1 | 0.998 | 0.998 | 500 | 6901 | 0.99 | 100.053826773 | 1 |
| E4 | 8.33270836458e-08 | 40002.000075 | 2 | 0.999 | 0.999499874937 | 1999.49987494 | 27618 | 0.99 | 95.3096429364 | 1 |
| E5 | 0.0005 | 1 | 256 | 0.999396187622 | 0.999997640648 | 423845.246141 | 5855744 | 0.99 | 22.398928728 | 1 |
| E6 | 8.33333333333e-05 | 1 | 101 | 7.30487595351e-07 | 0.869448157626 | 7.6597923232 | 101 | 0.99 | 1 | 1 |
| E7 | 0.005 | 1 | 1 | 0.998 | 0.998 | 500 | 6901 | 0.99 | 70.7106781187 | 1 |
| E8 | 0.00015625 | 1 | 256 | 0.999999978962 | 0.999999999918 | 12168207535.5 | 168109937664 | 0.99 | 29.2540990995 | 1 |
| E9 | 2.71539685163e-05 | 4.63543348483 | 129 | 0.284765879865 | 0.990310136634 | 103.200629587 | 1419 | 0.99 | 286.73128936 | 1 |
| E10 | 0.0008335 | 2.99940011998 | 155 | 0.213369692413 | 0.990083502578 | 100.842057177 | 1395 | 0.99 | 1.23692674537 | 1 |
| E11 | 6.79670595032e-09 | 28846.1538462 | 256 | 0.951228807613 | 0.999804704039 | 5120.43360906 | 70912 | 0.99 | 64225.2123507 | 1 |
| E12 | 5e-08 | 10000 | 1 | 0.9980000000000004 | 0.9980000000000004 | 500.00000000011056 | 6901 | 0.99 | 37330.0163189 | 1 |

備註：

- `t_mix_upper` 是保守上界，對某些鏈（例如 E8、E5）可能非常鬆。
- 即使數值很大，也不代表實際 mixing time 必然如此大；它只是 Dobrushin 上界。

---

## 4. Stepsize 與 Projection：完整實作定義

`t` 從 1 開始；`c = base`；`t0` 為 offset（本次預設 0）。

## 4.1 Stepsize schedules

1. `theory`

\[
\alpha_t=\frac{1}{c\cdot \max(\phi_{\max}^2,10^{-12})\cdot \max(\log(n_{steps}),1)\cdot \log(t+3)\cdot \sqrt{t+1}}
\]

2. `constant`

\[
\alpha_t = c
\]

3. `inv_t`

\[
\alpha_t = \frac{c}{\max(1,t+t_0)}
\]

4. `inv_sqrt_t`

\[
\alpha_t = \frac{c}{\sqrt{\max(1,t+t_0)}}
\]

5. `inv_omega_t`

\[
\alpha_t = \frac{c}{\max(\omega,10^{-12})\cdot \max(1,t+t_0)}
\]

## 4.2 Projection variants

每次 `w <- w + alpha_t * delta_t * phi(s_t)` 之後執行：

- `none`: 不投影
- `oracle`: 投影半徑
  \[
  R = ||\theta^*||_2
  \]
- `upper`: 投影半徑
  \[
  R = \frac{2r_{max}}{\sqrt{\omega}(1-\gamma)^{3/2}}
  \]

若 `||w||_2 > R`，做 radial rescale 到 `||w||_2 = R`，並累計 `proj_clip_count`。

---

## 5. 會記錄什麼資訊（log schema）

註：目前 C++ 原始輸出仍保留 `tau_proxy` 欄位（spectral proxy）。  
本報表的 TD instance mixing 解讀已改為 k-step Dobrushin 上界（見第 2.3、3.3 節）。

## 5.1 Console log（launcher / stdout）

- run 級設定：`n_steps, n_runs, threads, schedules, projections, base_values`
- 每個 case 的 `omega, kappa, tau_proxy`
- 每個 `(schedule, projection, base)` 的完成訊息與 `divergence_rate`

## 5.2 `manifest.tsv`（每個 run dir 一份）

每列是一個 `(case_id, schedule, projection, base)` 組合，主要欄位：

- `case_id, env_id, case_slug, case_label`
- `algorithm, schedule, projection, projection_radius`
- `param_name, param_value`
- `agg_file, run_file`
- `omega, kappa, tau_proxy, gamma, theta_star_norm, r_max, metadata`

## 5.3 `agg_*.csv`（聚合 checkpoint 曲線）

欄位：

- `timestep`
- `E_D[||Vbar_t - V*||^2]`
- `E_A[||Vbar_t - V*||^2]`
- `E[||theta_t||^2]`
- `max_i<=T ||theta_i||^2`
- `||theta^*||^2`
- `std_D, std_A, std_max_theta`
- `omega, kappa, tau_proxy, gamma`
- `alpha_mean, alpha_min, alpha_max`

## 5.4 `runs_*.csv`（每個 MC run 結果）

欄位：

- `run_idx`
- `diverged`（0/1）
- `diverged_at`
- `final_obj_D, final_obj_A`
- `final_theta_norm, max_theta_norm`
- `ratio_max_over_theta_star_sq`
- `theta_star_norm_sq`
- `max_alpha`
- `max_proj_clip_count`

## 5.5 Python summary TSV

- `plots/learning_curve_summary.tsv`：
  - `case_id, schedule, projection, param_value, omega, tau_proxy, final_D, final_A`
- `plots/omega_tau_summary.tsv`：
  - `case_id, schedule, projection, param_value, omega, tau_proxy, final_d, final_a`

---

## 6. 圖會畫多少張、每張定義是什麼

下列是目前 C++ pipeline 會生成的圖族（對齊 `plot_divergence.jl` parity + quick study）：

## 6.1 `plot_divergence_parity.py`

### (A) Final Triplet（每個 case 一張）

- 檔名：`{env}__final__{case_slug}.png`
- 子圖 1（Ratio）：
  - x: `param_value (c)`（log）
  - y: `max_theta_norm / ||theta*||^2`（log）
- 子圖 2（Divergence）：
  - x: `c`（log）
  - y: divergence rate（`runs_*.csv` 的 diverged 比例）
- 子圖 3（Final A objective）：
  - x: `c`（log）
  - y: 最後 checkpoint 的 `E_A[...]`（log）

### (B) Big Final Grid（每個 env 一張）

- 檔名：`{env}__finalgrid__rows-c.png`
- row = case，3 欄對應 Ratio / Divergence / Suboptimality(A)

### (C) Compact Grid（每個 env 一張）

- 檔名：`{env}__compact__rows-c.png`
- 從 case 中挑代表子集（最多 3 列），3 欄同上

### (D) Learning Curve Grid（每個 env 兩張）

- 檔名：
  - `{env}_learning_curves_grid_D.png`
  - `{env}_learning_curves_grid_A.png`
- 每個 case 一格
- x: time step `t`（log）
- y: `E_D[...]` 或 `E_A[...]`（log）
- legend: `c` 值（每個 decade 抽代表）

### (E) Best Curves by c（每個 env 一張）

- 檔名：`{env}__bestcurves__by-c.png`
- 對每個 case 選出 `final (D+A)` 最小的 `c`
- x: time step `t`（log）
- y: `E_D + E_A`（log）
- legend: case label

## 6.2 `plot_learning_curves.py`

### (F) Case Overlay Learning Curves（每個 case 一張）

- 檔名：`{case_slug}__learning_curves.png`
- 左圖：
  - x: `t`（log）
  - y: `E_D[...]`（log）
- 右圖：
  - x: `t`（log）
  - y: `E_A[...]`（log）
- legend: `schedule|projection|param`

## 6.3 `plot_omega_tau_study.py`

### (G) Omega/Tau Scatter（每個 env 一張）

- 檔名：`omega_tau_scatter.png`
- 左圖：
  - x: `omega`（log）
  - y: `final D objective`（log）
- 右圖：
  - x: `tau_proxy`（log）
  - y: `final D objective`（log）
- color: `schedule`
- marker: `projection`

### (H) Omega/Tau Heatmap（每個 env 一張）

- 檔名：`omega_tau_heatmap.png`
- x: `log10(omega)`
- y: `log10(tau_proxy)`
- color: 各 bin 的 `mean log10(final D objective)`
- 預設 `24x24` bins

## 6.4 圖數量統計（本次每 env 只有 1 case）

- parity 圖：`1 + 1 + 1 + 2 + 1 = 6` 張 / env
- case overlay：`1` 張 / env
- omega/tau：`2` 張 / env
- 合計：`9` 張 / env
- 全部 env（13 個）：`13 * 9 = 117` 張（若某 env 無有限 `omega/tau` 點則 scatter/heatmap 可能缺圖）

---

## 7. 一個重要的分析風險（你應該知道）

`plot_divergence_parity.py` 的 Final Triplet / Grid 指標是按 `case` 聚合，而不是先按 `schedule/projection` 分層；在「全演算法同跑」時，x 軸同一個 `c` 會混入不同 schedule/projection 的點。  
因此：

- parity 家族圖適合對齊舊版單 schedule（theory-only）情境
- 真正做「不同 stepsize 與 projected/unprojected 的公平比較」，更應優先看：
  - `plot_learning_curves.py` 的 `schedule|projection|param` overlay
  - 或另外做 `schedule x projection` 分面圖（建議下一步補）
