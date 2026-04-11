# E1~E12 TD 重要 Quantity 詳解（C++ 版本）

Date: 2026-04-04  
Repo: `/home/leew0a/codex/TDfullexperiments`  
Source code: `cpp/tdx.cpp`

## 共通定義

- 狀態轉移：`P`
- 平穩分佈：`D`
- 線性特徵：`Phi`
- 折扣：`gamma`（本次全都 `0.99`）
- 目標矩陣：
  \[
  G=(1-\gamma)\Phi^\top D\Phi
  \]
- 強凸常數：
  \[
  \omega=\lambda_{\min}(G),\quad
  \kappa=\lambda_{\max}(G)/\lambda_{\min}(G)
  \]
- mixing estimate（改用 k-step Dobrushin contraction）：
  \[
  \delta_k:=\delta(P^k),\quad
  \alpha_k:=\delta_k^{1/k},\quad
  \tau_{\alpha,k}:=\frac{1}{1-\alpha_k}
  \]
  對任意 \(t=qk+r\)（\(0\le r<k\)）有
  \[
  \delta(P^t)\le C_k\,\delta_k^q,\qquad
  C_k:=\max_{0\le r<k}\delta(P^r)
  \]
  因此 \(\sup_x\|xP^t-\pi\|_{\text{TV}}\le\delta(P^t)\) 給出上界
  \[
  t_{\text{mix}}^{\text{upper}}(k,\varepsilon)
  =k\left\lceil\frac{\log(\varepsilon/C_k)}{\log(\delta_k)}\right\rceil\quad(0<\delta_k<1)
  \]
  並選擇使 \(t_{\text{mix}}^{\text{upper}}\) 最小的 `best_k`。
- 投影半徑：
  - `R_oracle = ||theta*||_2`
  - \[
    R_{\text{upper}}=\frac{2r_{\max}}{\sqrt{\omega}(1-\gamma)^{3/2}}
    \]

本檔數值使用 nonzero-`theta*` 實驗設定（你指定那套 reward_mode/rho）讀自：

- `verification/instance_metrics_nonzero_20260403/instance_constants.tsv`
- `verification/kstep_dobrushin_mixing_eps1e-6.tsv`（`K=256`, `eps=1e-6`）

---

## 總覽表（E1~E12, k-step Dobrushin mixing）

| Env | n_states | d | phi_max_sq | omega | kappa | best_k | delta_bestk | alpha_bestk | tau_alpha_bestk | t_mix_upper(eps=1e-6) | \|\|theta*\|\|_2 | R_oracle | R_upper |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| E1 | 2 | 1 | 0.99990001 | 5.000000e-03 | 1.000000e+00 | 1 | 9.980000e-01 | 9.980000e-01 | 5.000000e+02 | 6901 | 1.021158e+00 | 1.021158e+00 | 2.828427e+04 |
| E2 | 2 | 2 | 0.50002499875 | 1.249906e-07 | 4.000200e+04 | 1 | 9.980000e-01 | 9.980000e-01 | 5.000000e+02 | 6901 | 1.180509e+04 | 1.180509e+04 | 5.657066e+06 |
| E3 | 2 | 2 | 0.50002499875 | 1.249906e-07 | 4.000200e+04 | 1 | 9.980000e-01 | 9.980000e-01 | 5.000000e+02 | 6901 | 1.000538e+02 | 1.000538e+02 | 5.657066e+06 |
| E4 | 3 | 2 | 0.50002499875 | 8.332708e-08 | 4.000200e+04 | 2 | 9.990000e-01 | 9.994999e-01 | 1.999500e+03 | 27618 | 9.530964e+01 | 9.530964e+01 | 6.928463e+06 |
| E5 | 20 | 20 | 1 | 5.000000e-04 | 1.000000e+00 | 256 | 9.993962e-01 | 9.999976e-01 | 4.238452e+05 | 5855744 | 2.239893e+01 | 2.239893e+01 | 8.944272e+04 |
| E6 | 21 | 20 | 1 | 8.333333e-05 | 1.000000e+00 | 101 | 7.304876e-07 | 8.694482e-01 | 7.659792e+00 | 101 | 1.000000e+00 | 1.000000e+00 | 2.190890e+05 |
| E7 | 2 | 1 | 0.5 | 5.000000e-03 | 1.000000e+00 | 1 | 9.980000e-01 | 9.980000e-01 | 5.000000e+02 | 6901 | 7.071068e+01 | 7.071068e+01 | 2.828427e+04 |
| E8 | 32 | 2 | 0.03125 | 1.562500e-04 | 1.000000e+00 | 256 | 9.9999998e-01 | 9.999999999e-01 | 1.216821e+10 | 168109937664 | 2.925410e+01 | 2.925410e+01 | 1.600000e+05 |
| E9 | 65 | 2 | 0.015625 | 2.715397e-05 | 4.635433e+00 | 129 | 2.847659e-01 | 9.903101e-01 | 1.032006e+02 | 1419 | 2.867313e+02 | 2.867313e+02 | 3.838074e+05 |
| E10 | 4 | 2 | 0.333366666667 | 8.335000e-04 | 2.999400e+00 | 155 | 2.133697e-01 | 9.900835e-01 | 1.008421e+02 | 1395 | 1.236927e+00 | 1.236927e+00 | 6.927511e+04 |
| E11 | 51 | 2 | 0.0196078431373 | 6.796706e-09 | 2.884615e+04 | 256 | 9.512288e-01 | 9.998047e-01 | 5.120434e+03 | 70912 | 6.422521e+04 | 6.422521e+04 | 2.425944e+07 |
| E12 | 20 | 2 | 0.050005 | 5.000000e-08 | 1.000000e+04 | 1 | 9.980000e-01 | 9.980000e-01 | 5.000000e+02 | 6901 | 3.733002e+04 | 3.733002e+04 | 8.944272e+06 |

備註：

- 此上界對部分鏈會很鬆（特別是 `delta_k` 非常接近 1 時，例如 E8）。
- 但它是 Dobrushin 框架下明確可驗證的保守上界。

---

## E1（alternating scalar）

### 結構

- `P = [[eps1,1-eps1],[1-eps1,eps1]]`, `eps1=1e-3`
- `Phi = [eps2/cphi, 1/cphi]`（`d=1`, `cphi=sqrt(1+eps2^2)`, `eps2=1e-2`）
- reward mode：`driven`（state2 reward=`rho=1`）

### 關鍵 quantity

- `omega=5e-3`, `kappa=1`
- `best_k=1`, `delta_bestk=0.998`
- `alpha_bestk=0.998`, `tau_alpha_bestk=500`
- `t_mix_upper(eps=1e-6)=6901`
- `phi_max_sq=0.99990001`
- `||theta*||_2=1.02115763234`
- `R_upper=2.828427e4`

### 解讀

- 條件數極好（`kappa=1`），本質上不是 ill-conditioned TD 幾何。
- 但 Dobrushin 的 \(\varepsilon\)-mixing 上界（`eps=1e-6`）仍偏大，屬保守估計。

---

## E2（sticky two-state block）

### 結構

- `P = [[1-eps1,eps1],[eps1,1-eps1]]`
- `Phi = [[1/cphi,0],[1/cphi,eps2/cphi]]`, `d=2`, `cphi=sqrt(2+eps2^2)`
- reward mode：`driven`

### 關鍵 quantity

- `omega=1.24990625469e-7`（非常小）
- `kappa=40002.000075`
- `best_k=1`, `delta_bestk=0.998`
- `alpha_bestk=0.998`, `tau_alpha_bestk=500`
- `t_mix_upper(eps=1e-6)=6901`
- `phi_max_sq=0.50002499875`
- `||theta*||_2=11805.088567`
- `R_upper=5.657066e6`

### 解讀

- 幾何上非常病態（`omega` 極小 + `kappa` 極大），對 stepsize 敏感。
- 同時 Dobrushin 上界也不小（`6901`），整體學習難度高。

---

## E3（alternating shear）

### 結構

- 轉移同 E1（alternating）
- 特徵同 E2（2D shear）
- reward mode：`driven`

### 關鍵 quantity

- `omega=1.24990625469e-7`
- `kappa=40002.000075`
- `best_k=1`, `delta_bestk=0.998`
- `alpha_bestk=0.998`, `tau_alpha_bestk=500`
- `t_mix_upper(eps=1e-6)=6901`
- `phi_max_sq=0.50002499875`
- `||theta*||_2=100.053826773`
- `R_upper=5.657066e6`

### 解讀

- 與 E2 幾何病態程度幾乎同級（`omega/kappa` 同量級），但 `||theta*||` 小很多。

---

## E4（metastable trap）

### 結構

- 3-state trap：`0->1`，`1`/`2` 以 `eps1` 在 trap 與出口間切換
- `Phi` 第 3 個 state 為零向量（退化方向）
- reward mode：`signed`（`[0,+1,-1]`）

### 關鍵 quantity

- `omega=8.33270836458e-8`
- `kappa=40002.000075`
- `best_k=2`, `delta_bestk=0.999`
- `alpha_bestk=0.999499874937`, `tau_alpha_bestk=1999.49987494`
- `t_mix_upper(eps=1e-6)=27618`
- `phi_max_sq=0.50002499875`
- `||theta*||_2=95.3096429364`
- `R_upper=6.928463e6`

### 解讀

- 同時具備「幾何病態 + mixing 上界很大」雙重困難。
- 這是最容易出現收斂慢/高方差的 stress instance 之一。

---

## E5（cycle transport）

### 結構

- `m=20` ring，前進為主、留在原地機率 `eps1=1e-2`
- `Phi = I_m`（`d=20`）
- reward mode：`single-site`（state0=1）

### 關鍵 quantity

- `omega=5e-4`, `kappa=1`
- `best_k=256`, `delta_bestk=0.999396187622`
- `alpha_bestk=0.999997640648`, `tau_alpha_bestk=423845.246141`
- `t_mix_upper(eps=1e-6)=5855744`
- `phi_max_sq=1`
- `||theta*||_2=22.398928728`
- `R_upper=8.944272e4`

### 解讀

- 幾何非常乾淨（`kappa=1`），但 k-step Dobrushin 上界非常鬆且巨大。

---

## E6（conveyor with reset）

### 結構

- `n_states=m+1=21`，state0 低機率發射到 conveyor，末端回 0
- `Phi` 對 `1..m` 為 shifted identity，state0 為 0 向量
- reward mode：`launch`（state1=1）

### 關鍵 quantity

- `omega=8.33333333333e-5`, `kappa≈1`
- `best_k=101`, `delta_bestk=7.30487595351e-07`
- `alpha_bestk=0.869448157626`, `tau_alpha_bestk=7.6597923232`
- `t_mix_upper(eps=1e-6)=101`
- `phi_max_sq=1`
- `||theta*||_2=1`
- `R_upper=2.190890e5`

### 解讀

- 幾何不病態，且在 k-step contraction 下可得到有限且不大的 mixing 上界。

---

## E7（persistent-sign forcing）

### 結構

- sticky 2-state
- `Phi=[1/sqrt(2),1/sqrt(2)]`（兩 state 同特徵）
- reward mode：`state1-only`（`[1,0]`）

### 關鍵 quantity

- `omega=5e-3`, `kappa=1`
- `best_k=1`, `delta_bestk=0.998`
- `alpha_bestk=0.998`, `tau_alpha_bestk=500`
- `t_mix_upper(eps=1e-6)=6901`
- `phi_max_sq=0.5`
- `||theta*||_2=70.7106781187`
- `R_upper=2.828427e4`

### 解讀

- 幾何和 mixing 都簡單，但 target 幅度（`theta*`）很大。

---

## E8（rotating-arc ring）

### 結構

- `m=32` ring
- `Phi_i=[cos(2pi i/m), sin(2pi i/m)]/sqrt(m)`, `d=2`
- reward mode：`single-harmonic`（`cos` 型）

### 關鍵 quantity

- `omega=1.5625e-4`, `kappa=1`
- `best_k=256`, `delta_bestk=0.999999978962`
- `alpha_bestk=0.999999999918`, `tau_alpha_bestk=12168207535.5`
- `t_mix_upper(eps=1e-6)=168109937664`
- `phi_max_sq=1/m=0.03125`
- `||theta*||_2=29.2540990995`
- `R_upper=1.6e5`

### 解讀

- 幾何乾淨（harmonic 正交結構），但 Dobrushin 上界極為保守且很大。

---

## E9（open excursion arc）

### 結構

- `n_states=65`，open excursion + reset（非閉環）
- `Phi_i=[cos(alpha_i), sin(alpha_i)]/sqrt(m)`, `alpha_i=alpha_max*(i+1)/m`, `alpha_max=pi/2`
- reward mode：`uniform`（excursion states 全 1）

### 關鍵 quantity

- `omega=2.71539685163e-5`
- `kappa=4.63543348483`
- `best_k=129`, `delta_bestk=0.284765879865`
- `alpha_bestk=0.990310136634`, `tau_alpha_bestk=103.200629587`
- `t_mix_upper(eps=1e-6)=1419`
- `phi_max_sq=1/64=0.015625`
- `||theta*||_2=286.73128936`
- `R_upper=3.838074e5`

### 解讀

- 相比 E8 幾何條件較差（但非極端），k-step 估計可得到有限 mixing 上界。

---

## E10（bow-tie cycle）

### 結構

- 4-state ring
- `Phi = ([1,0],[1,eps2],[0,1],[-1,eps2]) / sqrt(3)`, `eps2=1e-2`
- reward mode：`signed-cycle`（`[0,+1,0,-1]`）

### 關鍵 quantity

- `omega=8.335e-4`
- `kappa=2.99940011998`
- `best_k=155`, `delta_bestk=0.213369692413`
- `alpha_bestk=0.990083502578`, `tau_alpha_bestk=100.842057177`
- `t_mix_upper(eps=1e-6)=1395`
- `phi_max_sq=(1+eps2^2)/3=0.333366666667`
- `||theta*||_2=1.23692674537`
- `R_upper=6.927511e4`

### 解讀

- 中等條件數，mixing 快，屬於比較穩定可控的測試點。

---

## E11（diffusive corridor）

### 結構

- reflecting corridor，`m=50`，`n_states=51`
- `Phi` = 常數項 + 線性斜率項，`slope(i)=eps2*(2i-m)/m`
- reward mode：`linear`

### 關鍵 quantity

- `omega=6.79670595032e-9`（極小）
- `kappa=28846.1538462`
- `best_k=256`, `delta_bestk=0.951228807613`
- `alpha_bestk=0.999804704039`, `tau_alpha_bestk=5120.43360906`
- `t_mix_upper(eps=1e-6)=70912`
- `phi_max_sq=1/(m+1)=0.0196078431373`
- `||theta*||_2=64225.2123507`
- `R_upper=2.425944e7`

### 解讀

- 幾何病態且 mixing 慢，`theta*` 也非常大，是另一個高難度 instance。

---

## E12（two-cluster forcing）

### 結構

- 兩群 block chain，各群大小 `k=10`
- 群內轉移 `(1-eps1)`, 跨群 `eps1`
- `Phi`：第一群 slope `+eps2`，第二群 slope `-eps2`
- reward mode：`cluster-opposite`（第一群 +1，第二群 -1）

### 關鍵 quantity

- `omega=5e-8`
- `kappa=10000`
- `best_k=1`, `delta_bestk=0.9980000000000004`
- `alpha_bestk=0.9980000000000004`, `tau_alpha_bestk=500.00000000011056`
- `t_mix_upper(eps=1e-6)=6901`
- `phi_max_sq=(1+eps2^2)/(2k)=0.050005`
- `||theta*||_2=37330.0163189`
- `R_upper=8.944272e6`

### 解讀

- 中度到重度病態 + 慢 mixing，並且 target 幅度大。

---

## 補充：哪幾個最難

若用「小 `omega` + 大 `kappa` + 大 \(t_{\text{mix}}^{\text{upper}}\)」綜合看（注意此上界可能很鬆），困難度大致可分：

- 上界極大（很保守）：`E8`, `E5`, `E11`
- 高難：`E4`, `E12`, `E2`, `E3`, `E1`, `E7`
- 中等：`E9`, `E10`
- 相對簡單：`E6`

---

## 全部 Plot 設定（C++ pipeline 詳盡版）

本節對應三支繪圖腳本：

- `scripts/plot_divergence_parity.py`
- `scripts/plot_learning_curves.py`
- `scripts/plot_omega_tau_study.py`

並補充 `scripts/generate_cxx_html_report.py` 的圖嵌入規則。

### A. 圖的資料來源與欄位

每個 run dir（例如 `E4_YYYYMMDD_HHMMSS`）至少包含：

1. `manifest.tsv`（一列對應一個 `(case, schedule, projection, c)`）
2. `agg_case_...csv`（每個組合一條 checkpoint 聚合曲線）
3. `runs_case_...csv`（每個組合的 MC run 統計）

主要欄位定義：

- `manifest.tsv`：
  - `schedule`, `projection`, `param_value`（即 `c`）
  - `omega`, `kappa`, `tau_proxy`, `theta_star_norm`
  - `agg_file`, `run_file`
- `agg_*.csv`：
  - `timestep`
  - `E_D[||Vbar_t - V*||^2]`
  - `E_A[||Vbar_t - V*||^2]`
  - `E[||theta_t||^2]`
  - `max_i<=T ||theta_i||^2`
  - `||theta^*||^2`
  - `std_D`, `std_A`, `std_max_theta`
  - `alpha_mean`, `alpha_min`, `alpha_max`
- `runs_*.csv`：
  - `diverged`（0/1）
  - `diverged_at`
  - `ratio_max_over_theta_star_sq`
  - `max_proj_clip_count`

### B. 樣式與全域常數

#### B1. `plot_divergence_parity.py` 全域常數

- `Y_MIN_OBJ = 1e-6`, `Y_MAX_OBJ = 1e12`
- `Y_MIN_RATIO = 1e-6`, `Y_MAX_RATIO = 1e12`
- `CURVE_MIN_OBJ = 1e-6`, `CURVE_MAX_OBJ = 1e12`
- `PLOT_CAP_VALUE = 1e24`（超大值截斷上限）
- `--max-points` 預設：`PLOT_MAX_POINTS` 環境變數，否則 `2000`

#### B2. `plot_learning_curves.py` 顏色/線型

- schedule color:
  - `theory`: `#0d3b66`
  - `inv_t`: `#f95738`
  - `inv_sqrt_t`: `#3a86ff`
  - `inv_omega_t`: `#8338ec`
  - `constant`: `#2a9d8f`
- projection linestyle:
  - `none`: `-`
  - `oracle`: `--`
  - `upper`: `:`

#### B3. `plot_omega_tau_study.py` 顏色/marker

- schedule color 同 B2
- projection marker:
  - `none`: `o`
  - `oracle`: `s`
  - `upper`: `^`
- heatmap bins 預設：`24 x 24`

### C. 每一類圖的精確定義

## C1. `plot_divergence_parity.py` 產生的圖

### C1-1 Final Triplet（每個 case 一張）

- 檔名：`{env}__final__case-XXXX.png`
- figure size：`(16, 4.5)`
- 子圖 1（Ratio）：
  - x：`c=param_value`（log）
  - y：`max_i<=T ||theta_i||^2 / ||theta*||^2`（log）
  - y-limit：`[1e-6, 1e12]`
  - title：`Ratio`
- 子圖 2（Divergence）：
  - x：`c`（log）
  - y：`divergence_rate = (# diverged runs) / n_runs`（linear）
  - y-limit：`[-0.05, 1.05]`
  - title：`Divergence`
- 子圖 3（Final A objective）：
  - x：`c`（log）
  - y：`final E_A[||Vbar_t - V*||^2]`（log）
  - y-limit：`[1e-6, 1e12]`
  - title：`Final A objective`
- suptitle：`{case_label} | omega=... | kappa=...`

### C1-2 Big Final Grid（每個 env 一張）

- 檔名：`{env}__finalgrid__rows-c.png`
- figure size：`(15, 3.0*nrows)`，`nrows = #cases`
- row=case，三欄依序：
  - Ratio（log-log）
  - Divergence（x log / y linear）
  - Suboptimality(A)（log-log）

### C1-3 Compact Grid（每個 env 一張）

- 檔名：`{env}__compact__rows-c.png`
- figure size：`(15, 3.0*nrows_compact)`
- row 只取代表 case（最多 3 列），三欄同 C1-2

### C1-4 Learning Curves Grid（每個 env 兩張）

- 檔名：
  - `{env}_learning_curves_grid_D.png`
  - `{env}_learning_curves_grid_A.png`
- 每格一個 case
- x：`timestep + 1`（linear x，但通常資料近似 log-spacing checkpoints）
- y：D 或 A objective（log）
- y-limit：`[1e-6, 1e12]`
- suptitle：
  - `"{ENV} learning curves (D)"`
  - `"{ENV} learning curves (A)"`
- legend（僅第一格）：`c=<param>`

### C1-5 Best Curves by c（每個 env 一張）

- 檔名：`{env}__bestcurves__by-c.png`
- figure size：`(9, 6)`
- 對每個 case，先選「`final(D+A)` 最小」的 `c`
- 再畫該 `c` 的整條曲線：
  - x：`t`（log）
  - y：`E_D + E_A`（log）
  - y-limit：`[1e-6, 1e12]`
- legend：case label

### C1-6 parity 腳本特殊規則（重要）

1. 會先做數值清洗：非有限值跳過、超大值截斷到 `1e24`。  
2. `Final Triplet / Grid` 是「按 case 聚合」，不是先拆 `schedule/projection`；同一 `c` 可能混有不同演算法點。  
3. 每張圖輸出 PNG，並嘗試另存 EPS（失敗就略過）。

## C2. `plot_learning_curves.py` 產生的圖

### C2-1 Case Overlay Learning Curves（每個 case 一張）

- 檔名：`{case_slug}__learning_curves.png`
- figure size：`(14, 5)`, `dpi=150`
- 左圖（Objective D）：
  - x：`timestep`（log）
  - y：`E_D[||Vbar_t-V*||^2]`（log）
  - title：`Objective D`
- 右圖（Objective A）：
  - x：`timestep`（log）
  - y：`E_A[||Vbar_t-V*||^2]`（log）
  - title：`Objective A`
- legend label：`{schedule}|{projection}|{param_value}`
- color：按 schedule；linestyle：按 projection
- suptitle：`Case {case_id}: {case_label}`

### C2-2 同時輸出 summary TSV

- 檔名：`learning_curve_summary.tsv`
- 欄位：
  - `case_id,schedule,projection,param_value,omega,tau_proxy,final_D,final_A`

## C3. `plot_omega_tau_study.py` 產生的圖

### C3-1 Omega/Tau Scatter

- 檔名：`omega_tau_scatter.png`
- figure size：`(14, 5)`, `dpi=150`
- 左圖：
  - x：`omega`（log）
  - y：`final D objective`（log）
  - title：`Final Error vs Omega`
- 右圖：
  - x：`tau_proxy`（log）
  - y：`final D objective`（log）
  - title：`Final Error vs Tau`
- color：schedule；marker：projection
- 只保留 `omega>0, tau>0, final_d>0` 且皆 finite 的點

### C3-2 Omega/Tau Heatmap

- 檔名：`omega_tau_heatmap.png`
- figure size：`(7, 6)`, `dpi=150`
- x：`log10(omega)`
- y：`log10(tau_proxy)`
- color：該 bin 的 `mean log10(final D objective)`
- title：`Omega/Tau Heatmap of Final Error`
- bins：`24 x 24`
- 若沒有任何有效點（例如全是 `tau=inf`），不會產圖

### C3-3 同時輸出 summary TSV

- 檔名：`omega_tau_summary.tsv`
- 欄位：
  - `case_id,schedule,projection,param_value,omega,tau_proxy,final_d,final_a`

### D. HTML report 的圖嵌入設定（`generate_cxx_html_report.py`）

每個 env 區塊預期嵌入以下圖（若不存在則顯示 missing 註記）：

1. Final Analysis Triplet  
2. Final Grid  
3. Compact Grid  
4. Learning Curves Grid (D)  
5. Learning Curves Grid (A)  
6. Best Curves by c  
7. Case Overlay Learning Curves  
8. Omega/Tau Scatter  
9. Omega/Tau Heatmap

`--self-contained` 時會把圖轉成 base64 data URI 內嵌。

### E. 圖數量公式（你要的總量）

設每個 env 有 `C` 個 case：

- parity family：`C + 1 + 1 + 2 + 1 = C + 5`
- case overlay：`C`
- omega/tau：`2`
- 合計：`2C + 7` 張 / env（若 omega/tau 無有效點則最多少 2 張）

本次設定每個 env 都是單一 case（`C=1`）：

- `9` 張 / env
- 13 env 上限 `117` 張
- `E6`、`E9` 因 `tau_proxy=inf`，通常各少 `2` 張 => 常見總數 `113`
