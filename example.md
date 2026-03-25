# 候選 TD(0) 反例／壓力測試環境（example.md）

這份檔案收集了我們前面構造過、而且**一度看起來有希望**的 TD(0) 例子。  
它們的角色是：

1. 當作不同的 **TD environment** 去直接模擬；
2. 看 iterates 的真實收斂／暫態行為；
3. 分辨到底是
   - mixing 慢造成的，
   - \(\lambda_{\min}\) 很小造成的，
   - 還是高維 transport / non-normal transient 造成的。

**重要說明：**  
下面的例子**不是都被證明是真正的 lower-bound counterexample**。  
有些例子被放進來，正是因為它們原本最像會出事；  
有些則是很好的「反駁型 control」：如果連它都不爆，那表示某類機制大概率走不通。

---

## 統一 TD(0) 設定

對每個 environment，都使用標準 discounted on-policy 線性 TD(0)：

\[
\theta_{t+1}
=
\theta_t + \eta_t \delta_t \phi(s_t),
\qquad
\delta_t = r(s_t) + \gamma \phi(s_{t+1})^\top \theta_t - \phi(s_t)^\top \theta_t.
\]

等價地，也可以寫成

\[
\theta_{t+1}
=
\theta_t - \eta_t(A_t\theta_t - b_t),
\qquad
A_t = \phi(s_t)(\phi(s_t)-\gamma\phi(s_{t+1}))^\top,
\quad
b_t = r(s_t)\phi(s_t).
\]

建議先固定一個學習率族：

\[
\eta_t = \frac{c_\eta}{\sqrt{t+t_0}\,\log(t+t_0+1)}, \qquad t\ge 0.
\]

建議的預設：

- \(\gamma = 0.95\) 或 \(0.99\)
- \(c_\eta \in \{0.1, 0.3, 1.0\}\)
- \(t_0 \in \{10, 100\}\)，避免前幾步太大
- 同時測兩種初始化：
  - \(\theta_0 = 0\)
  - \(\theta_0\) 對齊你懷疑最弱／最危險的方向
- 每個 environment 都建議跑兩版：
  - **零 reward 版**：隔離純乘法 transient
  - **非零 reward 版**：看 driven iterate / 固定點大小

建議記錄的量：

1. \(\|\theta_t\|_2\)
2. \(\max_{k\le t}\|\theta_k\|_2\)
3. 若可數值求 \(\theta^\*\)，記錄 \(\|\theta_t-\theta^\*\|_2\)
4. 沿著最弱方向（或你懷疑的危險方向）的投影
5. trap episode 長度 / excursion 長度
6. \(A_t\)、\(b_t\) 的自相關與經驗相關時間

---

## 特徵正規化（確保 bounded feature）

很多例子都先定義 raw feature \(\tilde\phi(s)\)，再做縮放：

\[
\phi(s) = \tilde\phi(s)/c_\Phi,
\]

其中 \(c_\Phi\) 選到足夠大，使得

\[
\lambda_{\max}(\Phi^\top \Phi)\le 1.
\]

這樣可以保證都留在你要的 bounded-feature regime 裡。

---

# E1：1 維 alternating-amplitude scalar test

## 目的

這是最乾淨的 **1 維診斷例子**。  
它用來測試：如果某些步真的有局部擴張，1 維裡能不能靠反覆出現的負 drift 累積出大 transient？

如果連這個都做不出像樣的 growth，那真正成功的例子大概率必須依賴更高維的 switching。

## 狀態與轉移

狀態空間：\(\{1,2\}\)

近乎交替的轉移矩陣：

\[
P_{\mathrm{alt}}(\epsilon_1)=
\begin{pmatrix}
\epsilon_1 & 1-\epsilon_1\\
1-\epsilon_1 & \epsilon_1
\end{pmatrix}.
\]

當 \(\epsilon_1\) 很小時，sample path 幾乎是 \(1\leftrightarrow 2\) 一直來回。

建議掃：

- \(\epsilon_1 \in \{10^{-2},10^{-3},10^{-4}\}\)

## 特徵

raw scalar feature：

\[
\tilde \phi(1)=\epsilon_2,\qquad \tilde \phi(2)=1.
\]

取正規化常數

\[
c_\Phi = \sqrt{1+\epsilon_2^2},
\qquad
\phi(i)=\tilde\phi(i)/c_\Phi.
\]

此時 \(\lambda_{\max}(\Phi^\top\Phi)=1\)。

建議掃：

- \(\epsilon_2 \in \{10^{-1},10^{-2},10^{-3}\}\)

## reward

建議兩版：

- **齊次版（pure transient）**：\(r(1)=r(2)=0\)
- **driven 版**：\(r(1)=0,\ r(2)=\rho\)，例如 \(\rho=1\)

## 為什麼一開始覺得有希望

在交替步 \(1\to 2\) 上，

\[
a_{12}=\phi(1)(\phi(1)-\gamma\phi(2))
\approx -\gamma\epsilon_2
\]

當 \(\epsilon_2\) 小時，這一步會局部擴張，所以看起來像是「每隔一步就能稍微放大一次」。

## 它真正測的是什麼

能不能讓

\[
\prod_t (1-\eta_t a_t)
\]

在 1 維裡真的長大，而不是最後被 telescoping 結構吃掉。

## 目前預期

這個例子**大概率不會**產生 \(e^{\sqrt{\tau}}\) 這種級別的 growth。  
它主要是拿來驗證：1 維 telescope barrier 在數值上是不是真的存在。

---

# E2：2 維 sticky two-state block test

## 目的

這是最直接的「slow mixing = 長時間卡在同一 state」測試。  
如果單靠長 dwell time 就足以讓 TD 出事，這個例子應該最容易看出來。

## 狀態與轉移

狀態空間：\(\{1,2\}\)

sticky 轉移矩陣：

\[
P_{\mathrm{sticky}}(\epsilon_1)=
\begin{pmatrix}
1-\epsilon_1 & \epsilon_1\\
\epsilon_1 & 1-\epsilon_1
\end{pmatrix}.
\]

建議掃：

- \(\epsilon_1 \in \{10^{-2},10^{-3},10^{-4}\}\)

## 特徵

raw 2 維 feature：

\[
\tilde \phi_1 =
\begin{pmatrix}
1\\0
\end{pmatrix},
\qquad
\tilde \phi_2 =
\begin{pmatrix}
1\\ \epsilon_2
\end{pmatrix}.
\]

安全正規化可取：

\[
c_\Phi = \sqrt{2+\epsilon_2^2},
\qquad
\phi_i = \tilde \phi_i/c_\Phi.
\]

這保證 \(\lambda_{\max}(\Phi^\top\Phi)\le 1\)。

建議掃：

- \(\epsilon_2 \in \{10^{-1},10^{-2},10^{-3},10^{-4}\}\)

## reward

建議兩版：

- **齊次版**：\(r(1)=r(2)=0\)
- **弱方向 forcing 版**：\(r(1)=0,\ r(2)=\rho\)，例如 \(\rho=1\)

## 為什麼一開始覺得有希望

因為 \(\epsilon_1\) 小時，會出現很長的同-state block。  
如果學習率完全不知道 \(\tau_{\text{mix}}\)，直覺上好像可能被某個 block 一直往外推。

## 它真正測的是什麼

在一段長 block 內，幾乎 \(s_t=s_{t+1}=i\)，所以更新近似

\[
A_t \approx (1-\gamma)\phi_i\phi_i^\top.
\]

也就是說，這個例子其實是直接測：

> 長時間看到**同一個 feature**，到底是在累積危險，還是在做收縮？

## 目前預期

目前預期它大多是 **block 內收縮**。  
這是一個很好的 negative control。

---

# E3：2 維 alternating shear candidate

## 目的

這是最自然的 **低維 non-normal switching 候選**。  
如果 2 維 on-policy TD(0) 真能靠 switching 製造出大的乘法 transient，這通常是第一個該跑的例子。

## 狀態與轉移

狀態空間：\(\{1,2\}\)

使用和 E1 相同的近乎交替矩陣：

\[
P_{\mathrm{alt}}(\epsilon_1)=
\begin{pmatrix}
\epsilon_1 & 1-\epsilon_1\\
1-\epsilon_1 & \epsilon_1
\end{pmatrix}.
\]

## 特徵

和 E2 一樣：

\[
\tilde \phi_1 =
\begin{pmatrix}
1\\0
\end{pmatrix},
\qquad
\tilde \phi_2 =
\begin{pmatrix}
1\\ \epsilon_2
\end{pmatrix},
\qquad
\phi_i = \tilde \phi_i/\sqrt{2+\epsilon_2^2}.
\]

## reward

建議兩版：

- **齊次版**：\(r(1)=r(2)=0\)
- **driven 版**：\(r(1)=0,\ r(2)=\rho\)，例如 \(\rho=1\)

## 有用的解析量

兩個交替更新對應

\[
A_{12} = \phi_1(\phi_1-\gamma\phi_2)^\top,
\qquad
A_{21} = \phi_2(\phi_2-\gamma\phi_1)^\top.
\]

自然的兩步 block 是

\[
M_t = (I-\eta_t A_{21})(I-\eta_t A_{12}).
\]

## 為什麼一開始覺得有希望

這個例子幾乎把低維裡所有危險元素都放進去了：

- 最強切換
- nearly collinear feature
- \(\epsilon_2\) 控制弱方向
- rank-1 non-commuting 更新
- 很像 shear / non-normal transient 的最小模型

## 它真正測的是什麼

反覆 \(1\leftrightarrow 2\) 切換，能不能讓 block product 的 norm 超過常數倍？

## 目前預期

這仍然是最值得跑的低維 transient 候選之一，  
但解析上看起來，兩步 block 的一階 drift 是 contractive，真正可能造成 bump 的只剩二階。  
所以比較可能看到的是 **常數倍 transient**，不是 \(e^{\sqrt{\tau}}\)。

---

# E4：3 狀態 metastable trap（\(\epsilon_1,\epsilon_2\) 可分離）

## 目的

這是最完整、也最貼近你原始問題的 2 維例子。  
它能把兩個旋鈕乾淨分開：

- \(\epsilon_1\)：控制 trap 長度 / mixing 相關時間
- \(\epsilon_2\)：控制弱方向 / \(\lambda_{\min}\)

如果你想實驗上拆開「mixing effect」和「weak restoring force」的角色，這是首選。

## 狀態與轉移

狀態空間：\(\{1,2,3\}\)

\[
P =
\begin{pmatrix}
0 & 1 & 0\\
1-\epsilon_1 & 0 & \epsilon_1\\
\epsilon_1 & 0 & 1-\epsilon_1
\end{pmatrix}.
\]

解讀：

- \(1\to 2\) 是 deterministic
- 從 \(2\) 出發：
  - 以機率 \(1-\epsilon_1\) 回到 \(1\)
  - 以機率 \(\epsilon_1\) 逃到 \(3\)
- 從 \(3\) 出發：
  - 以機率 \(1-\epsilon_1\) 留在 \(3\)
  - 以機率 \(\epsilon_1\) 回到 \(1\)

這會產生長時間待在 \(\{1,2\}\) 的 trap episode，典型長度是 \(\asymp 1/\epsilon_1\)。

這個例子有個不錯的性質：stationary distribution 是均勻的，

\[
\pi=(1/3,1/3,1/3).
\]

## 特徵

raw feature：

\[
\tilde \phi_1 =
\begin{pmatrix}
1\\0
\end{pmatrix},
\qquad
\tilde \phi_2 =
\begin{pmatrix}
1\\ \epsilon_2
\end{pmatrix},
\qquad
\tilde \phi_3 =
\begin{pmatrix}
0\\0
\end{pmatrix}.
\]

正規化：

\[
c_\Phi = \sqrt{2+\epsilon_2^2},
\qquad
\phi_i = \tilde \phi_i/c_\Phi.
\]

則 \(\lambda_{\max}(\Phi^\top\Phi)\le 1\)。

而且因為 \(D=\mathrm{diag}(1/3,1/3,1/3)\)，有

\[
\lambda_{\min}(\Phi^\top D \Phi)=\Theta(\epsilon_2^2).
\]

建議掃：

- \(\epsilon_1 \in \{10^{-2},10^{-3},10^{-4}\}\)
- \(\epsilon_2 \in \{10^{-1},10^{-2},10^{-3},10^{-4}\}\)

## reward

推薦三版：

- **齊次版**：\(r=(0,0,0)\)
- **弱方向 forcing**：\(r=(0,\rho,0)\)
- **signed forcing**：\(r=(0,\rho,-\rho)\)

例如 \(\rho=1\)。

## 為什麼一開始覺得有希望

這個例子是最像「候選 counterexample 工程」的：

- trap 長度可用 \(\epsilon_1\) 控
- \(\lambda_{\min}\) 可用 \(\epsilon_2\) 控
- 兩者獨立
- trap 內反覆打到弱方向
- 同時 chain 仍是 ergodic 的

## 它真正測的是什麼

這個例子可以拆開看三件事：

1. trap episode 夠長時，路徑會不會在弱方向累積很大偏移？
2. \(\epsilon_2\) 讓 restoring force 變弱後，forcing / noise 能累多久？
3. 大 iterates 是來自真正 transient，還是來自 \(\theta^\*\) 本身就變大？

## 目前預期

這是最值得拿來掃參數的 2 維 environment。  
我的目前預期是：

- \(\epsilon_2\) 小時，\(\theta^\*\) 的確可能很大；
- \(\epsilon_1\) 小時，forcing / noise 可以在 trap 內累比較久；
- 但若只看純乘法 transient，它很可能仍然不會自己長成真正的指數級，因為 trap 內的核心仍是 E3 那種 \(1\leftrightarrow 2\) 交替 block。

---

# E5：高維 cycle / ring transport test

## 目的

這是高維版的「Jordan chain / transport」直覺測試。  
如果任何 on-policy TD environment 能做出像「質量每一步往下一個座標搬運」那種大 transient，長 ring 是最自然的場所。

## 狀態與轉移

狀態空間：\(\{1,2,\dots,m\}\)

近乎週期的有向 ring：

\[
P(i\to i)=\epsilon_1,\qquad
P(i\to i+1 \!\!\!\!\pmod m)=1-\epsilon_1.
\]

建議掃：

- \(m \in \{10,20,50,100\}\)
- \(\epsilon_1 \in \{10^{-2},10^{-3}\}\)

**注意：**  
我沒有替這個例子推乾淨的精確 \(\tau_{\text{mix}}\) 公式。  
請先把它當成「長 directed geometry 的壓力測試」。

## 特徵

令參數維度 \(d=m\)，取 one-hot：

\[
\phi_i = e_i.
\]

此時 \(\Phi^\top\Phi = I_m\)，所以

\[
\lambda_{\max}(\Phi^\top\Phi)=1
\]

是精確成立的。

## reward

建議三版：

- **齊次版**：\(r(i)=0\)
- **single-site forcing**：\(r(1)=\rho,\ r(i)=0\) for \(i\neq 1\)
- **alternating forcing**：\(r(i)=(-1)^i \rho\)

## 為什麼一開始覺得有希望

對轉移 \(i\to i+1\)，TD 矩陣是

\[
A_{i,i+1}=e_i(e_i-\gamma e_{i+1})^\top.
\]

因此

\[
I-\eta_t A_{i,i+1}
=
I-\eta_t e_i e_i^\top + \eta_t\gamma e_i e_{i+1}^\top,
\]

它真的帶有明顯的 upper-shift / transport 味道。

## 它真正測的是什麼

在很長的 directed sequence 上，能不能在 cycle 關閉之前先出現顯著 transport bump？

## 目前預期

如果你想找「不是小 trap，而是長 transport 幾何」的 effect，這個例子非常值得跑。  
但因為它終究仍是個 **closed cycle**，也可能還是會被 cycle-contractivity 的一階結構壓住。

---

# E6：高維 conveyor-belt with reset sink

## 目的

這是把「長壞路徑（long bad path）」正式化後的版本。  
和 E5 不同，它不是小 cycle 一直轉，而是：

- 平常待在 reset / sink
- 偶爾發動一次長 excursion
- excursion 結束後再 reset

如果真的要避開「closed cycle 的一階收縮」，這類 directed excursion 比小 trap 更像候選。

## 狀態與轉移

狀態空間：\(\{0,1,2,\dots,m\}\)

轉移如下：

- 從 \(0\)：
  - 以機率 \(1-\epsilon_1\) 留在 \(0\)
  - 以機率 \(\epsilon_1\) 去 \(1\)
- 對 \(1\le i\le m-1\)：
  - deterministic 到 \(i+1\)
- 從 \(m\)：
  - deterministic 回到 \(0\)

也就是一條

\[
0 \to 1 \to 2 \to \cdots \to m \to 0
\]

的 conveyor-belt，平常卡在 0，偶爾發射一次長路徑。

建議掃：

- \(m \in \{10,20,50,100\}\)
- \(\epsilon_1 \in \{10^{-1},10^{-2},10^{-3}\}\)

**注意：**  
這裡我也沒有先給出 sharp \(\tau_{\text{mix}}\) 公式。  
先把 \(m\) 當作 excursion 長度、把 \(\epsilon_1\) 當作 launch rate 即可。

## 特徵

令 \(d=m\)，取

\[
\phi_0 = 0,\qquad
\phi_i = e_i \quad (1\le i\le m).
\]

則 \(\Phi^\top\Phi = I_m\)，所以 \(\lambda_{\max}(\Phi^\top\Phi)=1\)。

## reward

建議三版：

- **齊次版**：\(r(i)=0\)
- **launch forcing**：\(r(1)=\rho,\ r(i)=0\) for \(i\neq 1\)
- **excursion forcing**：\(r(i)=\rho\) for \(1\le i\le m\)，且 \(r(0)=0\)

## 為什麼一開始覺得有希望

這個例子是「危險的不該是小 trap 反覆 cycle，而該是一條長 directed path」的最自然有限狀態實現。

## 它真正測的是什麼

一次長 excursion 長度為 \(m\) 時，能不能在 reset 前造成隨 \(m\) 增長的明顯 transient？

## 目前預期

在所有高層想法裡，這是我最想拿來測「長 directed bad path 是否跟小 cycle 完全不同」的例子。  
它不保證成功，但非常值得跑。

---

# 如果只能先跑幾個，優先順序

如果我只能優先跑少數幾個，我會依序跑：

1. **E4：3-state metastable trap**  
   最貼近你的原始問題；\(\epsilon_1,\epsilon_2\) 可分離。

2. **E3：2D alternating shear**  
   最自然的低維 transient 候選。

3. **E6：高維 conveyor with reset**  
   最自然的「長壞路徑」候選。

4. **E5：高維 ring**  
   最自然的 closed-transport 候選。

5. **E2：sticky block**  
   測 slow mixing 單獨是否危險。

6. **E1：1D scalar**  
   用來驗證 1 維 telescope barrier。

---

# 每個 environment 在「診斷」什麼

- **E1**：1 維裡，局部擴張可不可以累積？
- **E2**：長時間待在同一 state 會不會危險？
- **E3**：2 維 switching + non-normality 能不能單獨做出大 transient？
- **E4**：mixing 慢與弱方向能不能被乾淨拆開？
- **E5**：長 closed transport path 能不能產生高維 transient？
- **E6**：長 directed excursion 能不能避開小 cycle 的收縮障礙？

---

# 目前的高層預判

可以把它們分成兩類。

## A 類：比較像是 bounded / mild transient 的候選
- E1
- E2
- E3
- E4（至少對純乘法 transient 來說）

這些例子大多卡在「一階不壞，只剩二階 bump」的障礙上。

## B 類：更 speculative，但最值得 numerically stress test
- E5
- E6

這兩個是在測試「長 transport 幾何」是否跟小 trap / 小 cycle 的現象根本不同。

---

# 最小 TD 模擬 pseudocode

```python
theta = theta0.copy()
s = s0

for t in range(T):
    s_next = sample_from_row(P[s])
    delta = r[s] + gamma * phi[s_next].T @ theta - phi[s].T @ theta
    eta = c_eta / (math.sqrt(t + t0) * math.log(t + t0 + 1))
    theta = theta + eta * delta * phi[s]
    s = s_next
```

若要跟 \(\theta^\*\) 比較，可先數值計算

\[
\bar A = \sum_{s,s'} \pi(s)P(s,s')\,\phi(s)(\phi(s)-\gamma\phi(s'))^\top,
\qquad
\bar b = \sum_s \pi(s)\,r(s)\phi(s),
\]

再解

\[
\theta^\* = \bar A^{-1}\bar b
\]

（若 \(\bar A\) 可逆）。

---

# 最後一句總結

這些例子對應了我們一路試過、覺得最有希望的幾種機制：

1. slow mixing 造成長壞事件；
2. 近共線 feature 反覆切換；
3. \(\lambda_{\min}\) 很小造成弱 restoring force；
4. 長 directed transport 幾何；
5. reward / Markov noise 沿弱方向累積。

所以它們很適合拿來真的跑 TD，看哪個機制會在數值上留下痕跡，哪個只是 proof-level 的幻影。

---

# 第二輪補充：更多值得跑的候選環境（E7–E12）

下面這批例子，是在第一輪之後補上的。它們刻意補齊了前一版清單的缺口：

1. **slow-mixing forcing**（不是靠乘法 transient，而是靠長相關時間的外力累積）；
2. **fixed low dimension but many effective directions**（在 2 維裡用很多狀態去模擬長 transport）；
3. **open excursion**（避開「短 closed cycle 的一階收縮」這個障礙）；
4. **diffusive slow mixing**（不是 trap / 週期，而是擴散造成的慢混合）。

如果你的目標是「真的數值上看 TD 會怎麼走」，這些例子很值得和 E3 / E4 / E6 一起比。

---

# E7：1 維 persistent-sign forcing（最乾淨的 mixing-forcing 測試）

## 目的

這個例子不是在測 non-normal transient，而是在測：

> **當 reward sign 由一個慢 mixing 的兩態鏈控制時，TD iterate 能不能因為長同號 run 而跑很遠？**

它是最乾淨的「mixing lower bound 候選」，因為幾乎把幾何因素全部拿掉了，只剩 persistent forcing。

## 狀態與轉移

狀態空間：\(\{+, -\}\)

sticky 兩態鏈：

\[
P =
\begin{pmatrix}
1-\epsilon_1 & \epsilon_1\\
\epsilon_1 & 1-\epsilon_1
\end{pmatrix}.
\]

建議掃：

- \(\epsilon_1 \in \{10^{-2},10^{-3},10^{-4}\}\)

典型 run length 約為 \(1/\epsilon_1\)。

## 特徵

raw scalar feature：

\[
\tilde\phi(+)=1,
\qquad
\tilde\phi(-)=1.
\]

正規化：

\[
c_\Phi = \sqrt{2},
\qquad
\phi(\pm)=1/\sqrt{2}.
\]

此時 \(\lambda_{\max}(\Phi^\top\Phi)=1\)。

## reward

\[
r(+)=+\rho,
\qquad
r(-)=-\rho.
\]

建議 \(\rho \in \{0.3,1,3\}\)。

## 為什麼有希望

這幾乎就是一個「受慢切換符號驅動」的線性遞迴：

\[
\theta_{t+1}
\approx
\bigl(1-(1-\gamma)\eta_t/2\bigr)\theta_t
+
\eta_t (\rho/\sqrt2)\,\sigma_t,
\]

其中 \(\sigma_t\in\{+1,-1\}\) 長時間保持同號。

如果 mixing 真的能在 pathwise 上把 iterate 拉大，這會是最容易看到的地方。

## 它測的是什麼

不是乘法 growth，而是：

- 長同號 forcing run 能不能把 \(\theta_t\) 推到 \(\sum_{k\le L}\eta_k\) 級別？
- restoring force \((1-\gamma)\) 會在多大程度上把它拉回來？
- 最大 excursion 對 \(\epsilon_1\) 的依賴比較像 \(L\)、\(\sqrt L\)、還是飽和成常數？

## 目前預期

這個例子很可能給出 **多項式級** 的大 excursion，
而不是指數級 transient。

如果你只想先確定「mixing 究竟能不能在真實路徑上把 iterate 拉大」，E7 是首選。

---

# E8：2 維 rotating-arc ring（固定 2 維但有很多有效方向）

## 目的

這個例子是在測：

> **雖然參數維度只有 2，但如果狀態很多、feature 角度慢慢轉，會不會模擬出長 transport / shear 的效果？**

它是對 E3（只有兩個方向來回切換）的直接補強。

## 狀態與轉移

狀態空間：\(\{1,2,\dots,m\}\)

有向 lazy ring：

\[
P(i\to i)=\epsilon_1,
\qquad
P(i\to i+1\!\!\!\pmod m)=1-\epsilon_1.
\]

建議掃：

- \(m \in \{16,32,64,128\}\)
- \(\epsilon_1 \in \{10^{-2},10^{-3}\}\)

## 特徵

令

\[
\alpha_i = \frac{2\pi(i-1)}{m},
\qquad
\tilde\phi_i=
\begin{pmatrix}
\cos\alpha_i\\
\sin\alpha_i
\end{pmatrix}.
\]

安全正規化可取：

\[
\phi_i = \tilde\phi_i/\sqrt{m}.
\]

這保證 \(\lambda_{\max}(\Phi^\top\Phi)\le 1\)。

## reward

推薦三版：

- **齊次版**：\(r(i)=0\)
- **single-harmonic forcing**：\(r(i)=\rho\cos\alpha_i\)
- **phase-shifted forcing**：\(r(i)=\rho\sin\alpha_i\)

## 為什麼有希望

這個例子和 E3 最大的不同，是它在 **固定 2 維裡放進很多角度**。  
如果真正危險的不是「兩點交替」，而是「長時間慢旋轉的方向 transport」，那 E8 比 E3 更接近那個機制。

## 它測的是什麼

- 長 closed path 上，慢旋轉 feature 會不會做出比兩點交替更大的 transient？
- 在固定 2 維中，「很多有效方向」是否足以繞開 E3 的障礙？
- reward 若跟 feature 相位鎖定，會不會出現明顯的 resonant growth？

## 目前預期

若它有大 bump，會非常有信息量，因為這代表「低維固定方向不夠，慢旋轉才是關鍵」。

如果它依然只出現常數倍 transient，那就表示：
**固定低維 + on-policy 結構** 可能真的很難做出大乘法增益。

---

# E9：2 維 open-excursion arc with reset（避開 closed-cycle 障礙）

## 目的

這是目前我最想補跑的一個 2 維候選。  
它專門拿來測試：

> **如果壞 path 不是 closed cycle，而是一條長的 open excursion，TD 會不會真的比較危險？**

這是在正面挑戰「closed cycle 一階收縮」這個障礙。

## 狀態與轉移

狀態空間：\(\{0,1,2,\dots,m\}\)

- \(0\to 1\) deterministic
- 對 \(1\le i < m\)：
  \[
  P(i\to i+1)=1-\epsilon_1,
  \qquad
  P(i\to 0)=\epsilon_1
  \]
- \(m\to 0\) deterministic

也就是說，鏈會不斷從 0 出發做一次 directed excursion，長度近似 geometric，平均約 \(1/\epsilon_1\)。

建議掃：

- \(m \in \{32,64,128\}\)
- \(\epsilon_1 \in \{10^{-2},10^{-3},10^{-4}\}\)

## 特徵

令 \(\phi_0=(0,0)^\top\)。對 \(i\ge 1\)，令

\[
\alpha_i = \frac{\alpha_{\max} i}{m},
\qquad
\tilde\phi_i=
\begin{pmatrix}
\cos\alpha_i\\
\sin\alpha_i
\end{pmatrix}.
\]

建議先取 \(\alpha_{\max}\in\{\pi/4,\pi/2,\pi\}\)。

安全正規化：

\[
\phi_i = \tilde\phi_i/\sqrt{m},
\qquad
\phi_0=0.
\]

## reward

推薦三版：

- **齊次版**：\(r(i)=0\)
- **uniform forcing**：\(r(i)=\rho\) for \(i\ge 1\)
- **late-excursion forcing**：\(r(i)=\rho\mathbf 1\{i\ge m/2\}\)

## 為什麼有希望

前面很多低維候選都困在「反覆小 cycle」裡。  
E9 的壞事件則是：

- 很長的一次 open excursion；
- 每一步都看到一個稍微不同的方向；
- 但在回到 0 之前，不會立刻形成短 closed cycle。

這讓它比 E3 / E4 更接近真正的「長壞路徑」。

## 它測的是什麼

- 一條長的 directed path，是否能在固定 2 維中做出更大的乘法或 forced growth？
- growth 對 excursion length 的依賴，是線性的、根號的，還是幾乎不長？
- \(\alpha_{\max}\) 越大時，會不會更容易出現 transient？

## 目前預期

E9 很值得重點看。  
如果你真的想找「低維 but not obviously impossible」的 pathwise 壞例子，E9 是目前最像樣的一個。

---

# E10：4 狀態 bow-tie cycle（超過兩步的最小低維 cycle）

## 目的

E3 測的是 2-step alternating。  
E10 則是想問：

> **兩步不夠壞，那四步 closed cycle 會不會比較壞？**

它是低維 closed-cycle 類裡最值得補的最小例子。

## 狀態與轉移

狀態空間：\(\{1,2,3,4\}\)

近 deterministic 4-cycle：

\[
P(i\to i)=\epsilon_1,
\qquad
P(i\to i+1\!\!\!\pmod 4)=1-\epsilon_1.
\]

建議掃：

- \(\epsilon_1 \in \{10^{-2},10^{-3},10^{-4}\}\)

## 特徵

raw feature：

\[
\tilde\phi_1 = \begin{pmatrix}1\\0\end{pmatrix},
\quad
\tilde\phi_2 = \begin{pmatrix}1\\\epsilon_2\end{pmatrix},
\quad
\tilde\phi_3 = \begin{pmatrix}0\\1\end{pmatrix},
\quad
\tilde\phi_4 = \begin{pmatrix}-1\\\epsilon_2\end{pmatrix}.
\]

這組 raw feature 的外積和是

\[
\sum_{i=1}^4 \tilde\phi_i\tilde\phi_i^\top
=
\begin{pmatrix}
3 & 0\\
0 & 1+2\epsilon_2^2
\end{pmatrix},
\]

所以可取精確正規化

\[
\phi_i = \tilde\phi_i/\sqrt{3}.
\]

建議掃：

- \(\epsilon_2 \in \{10^{-1},10^{-2},10^{-3}\}\)

## reward

推薦兩版：

- **齊次版**：\(r=(0,0,0,0)\)
- **signed cycle forcing**：\(r=(0,\rho,0,-\rho)\)

## 為什麼有希望

它是第一個真正超過 2-step 的低維 cycle。  
如果 closed cycle 的障礙只是在兩步的特殊對稱性上，那 E10 有機會比 E3 更壞。

## 它測的是什麼

- 4-step commutator 是否比 2-step 大很多？
- 不同幾何方向的 closed cycle，會不會累積出可見的 non-normal bump？
- \(\epsilon_2\) 變小時，bump 會不會明顯放大？

## 目前預期

E10 不一定會成功，但它是一個很好的「closed-cycle 極限測試」。  
若連它都沒有像樣 transient，那小維 closed-cycle 路徑大概率真的不是正路。

---

# E11：diffusive corridor（慢 mixing 來自擴散，而不是 trap）

## 目的

前面的慢 mixing 大多來自 trap / metastability / periodicity。  
E11 則改成一個完全不同的來源：

> **慢 mixing 來自一條長走廊上的擴散。**

這是用來檢查：

- 你看到的現象是不是只屬於 trap；
- 還是只要相關時間長，diffusive chain 也會把 TD 拉出明顯的 pathwise 偏移？

## 狀態與轉移

狀態空間：\(\{0,1,2,\dots,m\}\)

lazy reflecting random walk：

- 對 interior \(1\le i\le m-1\)
  \[
  P(i\to i)=1/2,
  \quad
  P(i\to i-1)=1/4,
  \quad
  P(i\to i+1)=1/4
  \]
- 端點反射，例如
  \[
  P(0\to 0)=3/4,
  \quad P(0\to 1)=1/4;
  \qquad
  P(m\to m)=3/4,
  \quad P(m\to m-1)=1/4.
  \]

這類鏈的 mixing time 大約是 \(\Theta(m^2)\) 級別。

建議掃：

- \(m \in \{20,50,100,200\}\)

## 特徵

raw 2 維 feature：

\[
\tilde\phi_i =
\begin{pmatrix}
1\\
\epsilon_2\,\frac{2i-m}{m}
\end{pmatrix}.
\]

安全正規化可取：

\[
\phi_i = \tilde\phi_i / \sqrt{(m+1)(1+\epsilon_2^2)}.
\]

建議掃：

- \(\epsilon_2 \in \{10^{-1},10^{-2},10^{-3}\}\)

## reward

推薦三版：

- **零 reward**：\(r_i=0\)
- **linear reward**：\(r_i=\rho\,\frac{2i-m}{m}\)
- **half-space reward**：\(r_i=\rho\,\mathrm{sign}(2i-m)\)

## 為什麼有希望

這個例子沒有小 trap，也沒有 deterministic cycle。  
如果 TD 的大 excursion 其實只需要「長 spatial correlation + 弱方向」，那 E11 應該會看得到。

## 它測的是什麼

- 擴散型慢 mixing 會不會單獨帶來大 pathwise deviation？
- 跟 E4 / E7 那種 metastable forcing 相比，它的最大 \(\|\theta_t\|\) 是更小、同級、還是更大？
- \(m\) 增大（即 \(\tau_{\mathrm{mix}}\) 增大）時，最大 excursion 的尺度如何成長？

## 目前預期

E11 很可能比較溫和，但它是非常重要的 control：  
如果只有 trap 類例子能拉大 iterate，而 diffusive slow mixing 幾乎不行，那就表示「慢 mixing 的幾何型態」比單純的 \(\tau_{\text{mix}}\) 數值本身更關鍵。

---

# E12：two-cluster metastable forcing（真正的 macro-state 慢切換）

## 目的

E7 太乾淨、E4 太偏小 trap。  
E12 想做的是更像「真正宏觀狀態慢切換」的情形：

- cluster A 內部很快混合；
- cluster B 內部也很快混合；
- A/B 之間很少切換。

這是最自然的 **metastable forcing** 模型。

## 狀態與轉移

令狀態空間是

\[
\{A_1,\dots,A_k,B_1,\dots,B_k\}.
\]

轉移規則：

- 從任一 \(A_i\) 出發：
  - 以機率 \(1-\epsilon_1\) 跳到均勻隨機的某個 \(A_j\)
  - 以機率 \(\epsilon_1\) 跳到均勻隨機的某個 \(B_j\)
- 從任一 \(B_i\) 出發對稱定義。

這樣 cluster 內 mixing 很快，但 macro-state 切換時間約為 \(1/\epsilon_1\)。

建議掃：

- \(k \in \{5,10,20\}\)
- \(\epsilon_1 \in \{10^{-2},10^{-3},10^{-4}\}\)

## 特徵

令 cluster 內 feature 常數：

\[
\tilde\phi_{A_i} = \begin{pmatrix}1\\ \epsilon_2\end{pmatrix},
\qquad
\tilde\phi_{B_i} = \begin{pmatrix}1\\ -\epsilon_2\end{pmatrix}.
\]

因為

\[
\sum_{i=1}^k \tilde\phi_{A_i}\tilde\phi_{A_i}^\top
+
\sum_{i=1}^k \tilde\phi_{B_i}\tilde\phi_{B_i}^\top
=
\begin{pmatrix}
2k & 0\\
0 & 2k\epsilon_2^2
\end{pmatrix},
\]

可取正規化

\[
\phi_s = \tilde\phi_s/\sqrt{2k}.
\]

建議掃：

- \(\epsilon_2 \in \{10^{-1},10^{-2},10^{-3},10^{-4}\}\)

## reward

推薦兩版：

- **cluster-opposite**：\(r(A_i)=+\rho,\ r(B_i)=-\rho\)
- **cluster-same-sign**：\(r(A_i)=r(B_i)=\rho\)

前者更偏 persistent forcing；後者更偏測試「弱方向 cancellation + slow switching」本身。

## 為什麼有希望

這個例子把三件事同時放進去了：

- 真正的 macro-state 慢切換；
- 內部快速平均（避免單一 state trap 的人工味道太重）；
- 可用 \(\epsilon_2\) 單獨控制弱方向。

如果 mixing 要進 lower bound，我很懷疑它更應該長這個樣子，而不是單個 state 的小 trap。

## 它測的是什麼

- 巨觀狀態的長同號 bias，會不會把 iterate 推到明顯大於 E7 的尺度？
- 內部 fast mixing 是否會削弱 pathwise 壞事件，還是幾乎不影響？
- 在 \(\epsilon_2\) 很小時，cluster-level forcing 是否會明顯堆到 weak direction？

## 目前預期

E12 很適合和 E7、E4 對照：

- E7：最乾淨的兩態 persistent forcing；
- E4：小 trap + 弱方向；
- E12：真正的 macro-state 慢切換 + 弱方向。

如果三者表現趨勢一致，那你就更能判斷：「真正關鍵的是 persistent forcing，還是 trap 幾何，還是 \(\lambda_{\min}\) 本身。」

---

# 第二輪補充的快速排名（建議先跑哪些）

若你想優先測「還沒被理論直接判死刑」的候選，我的排序是：

1. **E9：open-excursion arc with reset**  
   最像長壞路徑，最值得看。
2. **E12：two-cluster metastable forcing**  
   最像真正的 slow-mixing macro-state 模型。
3. **E8：rotating-arc ring**  
   固定 2 維裡測 many-effective-directions。
4. **E7：1D persistent-sign forcing**  
   最乾淨的 baseline，應該先跑來校準 mixing-forcing 尺度。
5. **E11：diffusive corridor**  
   很重要的 control，測試慢 mixing 的「型態」是否重要。
6. **E10：4-state bow-tie cycle**  
   值得補跑，但我對它能否真比 E3 更壞沒有那麼樂觀。

---

# 把 E1–E12 按機制重分組

## A. 純乘法／non-normal transient 類
- E1：1D alternating-amplitude scalar
- E3：2D alternating shear
- E8：2D rotating-arc ring
- E9：2D open-excursion arc with reset
- E10：4-state bow-tie cycle
- E5 / E6：高維 transport / conveyor-belt

## B. 慢 mixing forcing 類
- E7：1D persistent-sign forcing
- E11：diffusive corridor
- E12：two-cluster metastable forcing
- E4：3-state metastable trap（同時混合了小 trap 與 forcing）

## C. Negative control / barrier check 類
- E1：1D telescope barrier
- E2：sticky same-state block
- E3：兩點交替下的一階收縮
- E10：closed-cycle 是否真的比 2-step 更壞

