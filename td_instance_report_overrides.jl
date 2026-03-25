const GROUP_ORDER = ["A", "B", "C", "F"]
const GROUP_INFO = Dict{String,Dict{String,String}}(
    "A" => Dict(
        "label" => "A. 純乘法 / non-normal transient",
        "blurb" => "這一類把重點放在 switching 幾何與局部擴張。要看的不是單步 reward forcing，而是 sample path 上的乘法 transient 是否真的累積成大幅度偏移。",
    ),
    "B" => Dict(
        "label" => "B. 慢 mixing forcing",
        "blurb" => "這一類把重點放在長相關時間的外力或 macro-state persistency。要看的是 reward sign 或 cluster-level forcing 是否因為 mixing 很慢而把 iterate 拉遠。",
    ),
    "C" => Dict(
        "label" => "C. Negative control / barrier check",
        "blurb" => "這一類是障礙檢查與負控制。它們用來判斷哪些看似危險的 TD 例子，其實會被 telescope barrier、closed-cycle 收縮或同態 block 結構壓住。",
    ),
    "F" => Dict(
        "label" => "Unclassified / fallback",
        "blurb" => "這一區保留給 legacy run、原始 toyexample，或目前沒有對應 curated instance note 的輸出。報表仍會顯示參數、圖與可恢復的 metadata。",
    ),
)

function instance_record(env_id; display_name, mechanism_group_key, mechanism_tag, goal="", transition_summary="", feature_summary="", reward_summary="", why_promising="", what_it_tests="", expected_behavior="", primary_knobs=String[], reading_guide="", extra_roles=String[], source="builtin fallback")
    info = GROUP_INFO[mechanism_group_key]
    return Dict{String,Any}(
        "env_id" => env_id,
        "display_name" => display_name,
        "mechanism_group_key" => mechanism_group_key,
        "mechanism_group" => info["label"],
        "mechanism_group_blurb" => info["blurb"],
        "mechanism_tag" => mechanism_tag,
        "goal" => goal,
        "transition_summary" => transition_summary,
        "feature_summary" => feature_summary,
        "reward_summary" => reward_summary,
        "why_promising" => why_promising,
        "what_it_tests" => what_it_tests,
        "expected_behavior" => expected_behavior,
        "primary_knobs" => collect(String.(primary_knobs)),
        "reading_guide" => reading_guide,
        "extra_roles" => collect(String.(extra_roles)),
        "source" => source,
    )
end

function builtin_instance_catalog()
    catalog = Dict{String,Dict{String,Any}}()
    catalog["toyexample"] = instance_record(
        "toyexample";
        display_name="Original threshold sweep",
        mechanism_group_key="F",
        mechanism_tag="reference threshold sweep",
        goal="這是原始 repo 的 reference environment。它固定在一個有限狀態 toy MDP 上，主要掃 feature scale、eigen regime 與 theory schedule 常數 c。",
        transition_summary="原始 toyexample 使用固定 finite-state 結構，重點不是換環境家族，而是沿著 scale / eigen / kappa 的幾何掃描看 threshold 位置怎麼改變。",
        feature_summary="特徵方向與特徵尺度是主要操控項；viewer 會把 scale、eigen、kappa 當成此例子的主要 case knobs。",
        reward_summary="沿用原本 toyexample 的 reward / fixed-point 設定，主要目的是對照不同幾何與 schedule 下的收斂或發散邊界。",
        why_promising="它提供最完整、最早的 baseline sweep，所以適合拿來對照新加入的 E1–E12 機制型環境。",
        what_it_tests="主要診斷原始 threshold 問題對 scale、eigen、kappa 和 c 的敏感度，而不是針對單一新機制做 isolated diagnosis。",
        expected_behavior="應該呈現相對平滑的 threshold 變化，適合作為後續多種 TD instance 的參考基線。",
        primary_knobs=["scale", "eigen", "kappa"],
        reading_guide="先看 final grid 與 best curves，確認 threshold 大致落在哪些 c 區間；再回頭比各個 scale / eigen 組合，判斷原始幾何如何改變穩定區間。",
        source="builtin curated",
    )
    catalog["E1"] = instance_record("E1"; display_name="1 維 alternating-amplitude scalar test", mechanism_group_key="A", mechanism_tag="alternating scalar / telescope barrier", goal="最乾淨的 1D 診斷例子，用來看局部擴張在一維裡能不能真的累積成大 transient。", transition_summary="兩態近乎交替鏈，eps1 越小越接近 1↔2 強制來回。", feature_summary="單一 scalar feature，phi(1) 很小、phi(2) 接近 1，形成明顯 amplitude imbalance。", reward_summary="可用 zero reward 隔離 pure transient，也可用 driven reward 看固定點如何被推動。", why_promising="1→2 步在小 eps2 時會局部擴張，看起來像每隔一步都能稍微放大。", what_it_tests="檢查一維 local expansion 是否會被 telescope barrier 吃掉。", expected_behavior="大概率是 barrier check，不太像真正的強發散例子。", primary_knobs=["eps1", "eps2", "reward_mode", "rho"], reading_guide="把它當成 1D barrier sanity check。若多數 c 下仍只出現有限 transient，代表 telescope barrier 在數值上確實很強。", extra_roles=["also used as negative control"], source="builtin curated")
    catalog["E2"] = instance_record("E2"; display_name="2 維 sticky two-state block test", mechanism_group_key="C", mechanism_tag="sticky block / same-state barrier", goal="最直接的 slow-mixing same-state block 測試，檢查長時間卡在同一 state 是否足以造成有意義的增長。", transition_summary="兩態 sticky 鏈，eps1 控制停留在原 state 的時間。", feature_summary="兩維 block-like feature，重點是長時間同態更新時的收縮或放大。", reward_summary="可切 pure transient 或 driven reward，看 slow mixing 本身與 forcing 的差別。", why_promising="同一 state 連續出現時，若 block 幾何有弱方向，可能累積可觀偏移。", what_it_tests="檢查 sticky same-state dynamics 是否真的能突破簡單 block 收縮障礙。", expected_behavior="更像負控制；若仍穩定，代表只靠 same-state persistence 不夠。", primary_knobs=["eps1", "eps2", "reward_mode", "rho"], reading_guide="重點不是找最誇張 divergence，而是確認 sticky block 是否仍被 barrier 壓住。看 divergence-by-c 時，要特別比較 zero reward 與 driven reward。", source="builtin curated")
    catalog["E3"] = instance_record("E3"; display_name="2 維 alternating shear candidate", mechanism_group_key="A", mechanism_tag="alternating shear", goal="用低維 switching shear 機制測試真正的乘法 transient 是否能在 2D 裡出現。", transition_summary="小狀態空間下交替切換不同線性更新方向。", feature_summary="2D feature 讓不同 state 對應不同 shear / weak-direction 幾何。", reward_summary="可用 zero reward 看純乘法效應，也可加入 driven 版看 fixed-point 放大。", why_promising="比 E1 多了一個方向自由度，有機會讓 non-normal switching 累積而不是被單純 telescope 掉。", what_it_tests="檢查 2D alternating shear 是否已足夠產生明顯 transient amplification。", expected_behavior="若成功，應比 E1 更接近真正的乘法 growth；若失敗，代表低維 closed switching 仍有強障礙。", primary_knobs=["eps1", "eps2", "reward_mode", "rho"], reading_guide="先看 case final plots 是否真的比 E1 更常出現放大，再看 learning curves 是否只是短暫 transient 還是整段都被拉高。", extra_roles=["also used as barrier check"], source="builtin curated")
    catalog["E4"] = instance_record("E4"; display_name="3 狀態 metastable trap", mechanism_group_key="B", mechanism_tag="metastable trap + forcing", goal="把小 trap、慢 mixing 和 reward forcing 混在一起，測試 trap persistence 是否能把 TD iterate 長時間困在不利方向。", transition_summary="三態 metastable 結構，eps1 / eps2 分別控制 trap 內停留與逃逸。", feature_summary="低維 feature 對 trap state 與 escape state 採不同方向，讓弱方向與慢 mixing 同時出現。", reward_summary="支援 zero / weak / signed 等模式，用來分離純結構與 sign forcing。", why_promising="metastable trap 可以把路徑鎖在特定符號或幾何段落很久，比單純二態 sticky 更接近真正的 slow-mixing forcing。", what_it_tests="檢查 trap persistence 加上 reward sign 結構，是否會產生比單純 alternating / sticky 更大的 pathwise excursion。", expected_behavior="應該比 E1/E2 更容易看見大 excursion，但通常仍偏多項式或 long-transient，而非極端指數爆炸。", primary_knobs=["eps1", "eps2", "reward_mode", "rho", "gamma"], reading_guide="把它視為混合型例子。先看 reward_mode 之間的差異，再看 eps1 / eps2 改變 trap time 後，divergence rate 是否一起上升。", source="builtin curated")
    catalog["E5"] = instance_record("E5"; display_name="高維 cycle / ring transport test", mechanism_group_key="A", mechanism_tag="high-dimensional transport ring", goal="用高維 ring transport 測試很多有效方向沿 cycle 搬運時，乘法 transient 能否持續累積。", transition_summary="m 個 state 的 cycle / ring 結構，路徑沿著長 transport 回圈移動。", feature_summary="高維 feature 讓不同位置對應不同 transport direction。", reward_summary="支援 zero、single-site、alternating 等 reward，用來區分 transport 本身與 forcing 的作用。", why_promising="即使單一步不大，長 transport path 可能把能量一路搬到新的方向。", what_it_tests="檢查高維長 cycle 是否比小 closed cycle 更容易維持 multiplicative growth。", expected_behavior="如果 transport 機制重要，E5 會比低維 closed-cycle 例子更常出現持續放大。", primary_knobs=["m", "eps1", "reward_mode", "rho"], reading_guide="先比較不同 m 的 final plots，再看 best curves。若 m 越大越容易拉開，代表 effective transport length 是關鍵。", source="builtin curated")
    catalog["E6"] = instance_record("E6"; display_name="高維 conveyor-belt with reset sink", mechanism_group_key="A", mechanism_tag="transport with reset sink", goal="在高維 transport 上加入 reset sink，檢查 open transport 與 periodic reset 的平衡會不會比純 cycle 更容易做出大 transient。", transition_summary="conveyor-belt 路徑會往前 transport，但會定期被 reset 到 sink / launch 區。", feature_summary="高維 feature 捕捉 transport direction 與 sink / launch 幾何。", reward_summary="支援 zero、launch、excursion 等模式，用來看 forcing 是在起點還是 excursion 段最有效。", why_promising="相較 closed cycle，reset 讓路徑更接近 open excursion，可能減少簡單閉環收縮。", what_it_tests="檢查長 transport 加 reset 是否能避開 closed-cycle barrier。", expected_behavior="通常會比純 ring 更接近 open-excursion 行為，是高維 transport 類的關鍵比較對象。", primary_knobs=["m", "eps1", "reward_mode", "rho"], reading_guide="看不同 reward_mode 是否把放大集中在 launch 還是 excursion 段。若 open transport 真的重要，E6 應比 E5 更早出現大 excursion。", source="builtin curated")
    catalog["E7"] = instance_record("E7"; display_name="1 維 persistent-sign forcing", mechanism_group_key="B", mechanism_tag="persistent sign forcing", goal="最乾淨的 mixing-forcing 測試，把幾何幾乎拿掉，只剩慢切換 reward sign。", transition_summary="兩態 sticky sign chain，eps1 越小，正負號 run length 越長。", feature_summary="兩態共享同一 scalar feature，故幾何幾乎固定。", reward_summary="reward 直接等於 ±rho，是最純粹的 sign forcing。", why_promising="若 mixing 本身能在路徑上把 iterate 拉大，這種 persistent forcing 最容易看出來。", what_it_tests="檢查長同號 forcing run 是否足以把 theta_t 推到明顯更大的級別。", expected_behavior="較可能是多項式級 excursion，而不是極端乘法爆炸。", primary_knobs=["eps1", "rho"], reading_guide="把 attention 放在 rho 與 eps1。若 eps1 變小時曲線系統性升高，代表慢 mixing forcing 的效應是真實的。", source="builtin curated")
    catalog["E8"] = instance_record("E8"; display_name="2 維 rotating-arc ring", mechanism_group_key="A", mechanism_tag="rotating arc in fixed 2D", goal="在固定 2D 裡用很多 state 模擬很多有效方向，測試長 transport 是否能在低維投影裡出現。", transition_summary="state 沿 ring 走動，但 feature direction 在 2D 平面上逐步旋轉。", feature_summary="所有 feature 都在 2D 內，但相位沿 arc 慢慢轉，製造很多有效方向。", reward_summary="支援 zero、single-harmonic、phase-shifted 等模式。", why_promising="雖然只有 2D，但如果相位轉動夠慢，仍可能累積類似高維 transport 的效果。", what_it_tests="檢查 fixed low dimension 是否仍能靠多 state phase transport 做出顯著 transient。", expected_behavior="若它成功，說明有效方向數比 ambient dimension 更重要。", primary_knobs=["m", "eps1", "reward_mode", "rho"], reading_guide="看不同 m 是否拉開結果，以及 reward 相位是否和 feature 相位鎖定。這能分辨 transport 本身與 resonant forcing 的作用。", source="builtin curated")
    catalog["E9"] = instance_record("E9"; display_name="2 維 open-excursion arc with reset", mechanism_group_key="A", mechanism_tag="open excursion arc", goal="刻意避開 closed-cycle 障礙，用 open excursion + reset 測試非閉環 transport 的累積效果。", transition_summary="路徑沿 arc 往前推進，到末端後 reset 回起點，而不是形成短閉環。", feature_summary="2D arc feature 讓方向沿 excursion 漸變。", reward_summary="支援 zero、uniform、late-excursion 等 reward，用來看 forcing 放在哪段最有效。", why_promising="open excursion 比 closed cycle 更不容易被簡單一階收縮抵消。", what_it_tests="檢查避開 closed-cycle 後，transport 型 transient 是否更清楚地浮現。", expected_behavior="它應該比 E8 / E10 更像真正的 open transport 測試。", primary_knobs=["m", "eps1", "alpha_max", "reward_mode", "rho"], reading_guide="先看 alpha_max 與 m 的互動，再比較 uniform 與 late-excursion reward。若後段 forcing 明顯更強，代表 excursion 終段才是關鍵。", source="builtin curated")
    catalog["E10"] = instance_record("E10"; display_name="4 狀態 bow-tie cycle", mechanism_group_key="A", mechanism_tag="minimal multi-step cycle", goal="用最小低維多步 cycle 測試：超過兩步的 closed cycle 是否已經能比 2-step 更危險。", transition_summary="四態 bow-tie / multi-step cycle，比二態交替多出更長的閉環。", feature_summary="低維 feature 讓不同 state 在 cycle 中對應不同方向。", reward_summary="支援 zero 與 signed-cycle reward。", why_promising="若 closed cycle 真有額外危險性，最小可觀察版本應該在這裡就會露出來。", what_it_tests="檢查 closed-cycle 長度增加後，是否真的比 2-step alternating 更壞。", expected_behavior="常作為 closed-cycle barrier check；若仍不夠強，代表 open excursion 更關鍵。", primary_knobs=["eps1", "eps2", "reward_mode", "rho"], reading_guide="用它和 E3、E9 對照。若 E10 仍弱而 E9 明顯更強，代表 open excursion 比多步 closed cycle 更重要。", extra_roles=["also used as barrier check"], source="builtin curated")
    catalog["E11"] = instance_record("E11"; display_name="diffusive corridor", mechanism_group_key="B", mechanism_tag="diffusive slow mixing", goal="測試慢 mixing 是否可以來自擴散，而不是 trap 或短週期 persistence。", transition_summary="狀態在 corridor 上作 diffusive walk，mixing slow 來自擴散時間而非 sticky trap。", feature_summary="feature 沿 corridor 緩慢變化，讓擴散路徑把 iterate 暴露在不同局部幾何。", reward_summary="支援 zero、linear、half-space 等 reward。", why_promising="它把 slow mixing 與 trap 解耦，能檢查真正的 diffusive persistence 是否足以放大 TD。", what_it_tests="檢查沒有顯式 trap 時，純擴散造成的慢 mixing 能否產生大 excursion。", expected_behavior="若結果仍明顯，表示慢 mixing 本身就很關鍵，不必依賴 trap。", primary_knobs=["m", "eps2", "reward_mode", "rho"], reading_guide="看 m 與 reward_mode。若 corridor 長度增加就明顯提高 excursion，表示 diffusive mixing time 真正在驅動結果。", source="builtin curated")
    catalog["E12"] = instance_record("E12"; display_name="two-cluster metastable forcing", mechanism_group_key="B", mechanism_tag="macro-state slow switching", goal="用真正的兩群 macro-state 慢切換，測試 metastable forcing 是否比單一 sticky sign 更接近大尺度現象。", transition_summary="state 分成兩個 cluster，cluster 內快 mixing、cluster 間慢切換。", feature_summary="feature 同時編碼 cluster 內局部差異與 cluster-level sign / direction。", reward_summary="cluster-opposite 與 cluster-same-sign 是主要比較。", why_promising="這是最接近 macro-state persistency 的 forcing 例子，比 E7 更像真實 slow-switching 結構。", what_it_tests="檢查 cluster 間慢切換是否能把 iterate 長時間鎖在同一大方向上。", expected_behavior="若 metastable forcing 是核心，E12 應該比單一兩態 sticky sign 更穩定地做出大 excursion。", primary_knobs=["k", "eps1", "eps2", "reward_mode", "rho"], reading_guide="先比較兩個 reward_mode，再看 eps1 / eps2 是否把 cluster-level persistence 拉長。若 same-sign 與 opposite 呈現明顯不同，代表 macro forcing 結構真的重要。", source="builtin curated")
    catalog["unknown"] = instance_record(
        "unknown";
        display_name="Uncatalogued TD instance",
        mechanism_group_key="F",
        mechanism_tag="uncatalogued",
        goal="這個 run 有完整輸出，但目前沒有對應的 curated instance note。",
        transition_summary="viewer 會保留可恢復的 run metadata、圖與 CSV，讓你仍能讀到實驗配置。",
        feature_summary="若 manifest 或 legacy 檔名含有 feature-related metadata，它會顯示在 case tables 與 file inventory。",
        reward_summary="reward 結構未知；請參考 metadata 與 plot labels。",
        what_it_tests="目前只能從 manifest、legacy filename 與圖形行為反推。",
        expected_behavior="這一類頁面著重於 preserving observability，而不是提供事先寫好的機制解釋。",
        primary_knobs=String[],
        reading_guide="先看 Batch Parameters、Parameter Regime Summary 與 Case Interpretation Table，再用 plots 驗證這個 run 真正掃了哪些軸。",
        source="generic fallback",
    )
    return catalog
end
normalize_text(text) = replace(replace(String(text), "\r\n" => "\n"), '\r' => '\n')

function collapse_text(text)
    chunks = String[]
    for raw in split(normalize_text(text), '\n')
        line = strip(raw)
        isempty(line) && continue
        line == "---" && continue
        startswith(line, "- ") && (line = strip(line[3:end]))
        startswith(line, ">") && (line = strip(line[2:end]))
        isempty(line) || push!(chunks, line)
    end
    return strip(replace(join(chunks, " "), r"\s+" => " "))
end

function excerpt(text; limit=160)
    plain = collapse_text(text)
    isempty(plain) && return "not recorded"
    return length(plain) <= limit ? plain : string(first(plain, limit), "…")
end

function render_markdownish(text)
    body = normalize_text(text)
    lines = split(body, '\n')
    parts = String[]
    paragraph = String[]
    function flush_paragraph!()
        isempty(paragraph) && return
        push!(parts, "<p>" * esc_html(strip(join(paragraph, " "))) * "</p>")
        empty!(paragraph)
    end
    i = 1
    while i <= length(lines)
        line = strip(lines[i])
        if isempty(line) || line == "---"
            flush_paragraph!()
        elseif startswith(line, "- ")
            flush_paragraph!()
            items = String[]
            while i <= length(lines)
                candidate = strip(lines[i])
                startswith(candidate, "- ") || break
                push!(items, "<li>" * esc_html(strip(candidate[3:end])) * "</li>")
                i += 1
            end
            push!(parts, "<ul>" * join(items, "") * "</ul>")
            continue
        elseif startswith(line, ">")
            flush_paragraph!()
            quoted = String[]
            while i <= length(lines)
                candidate = strip(lines[i])
                startswith(candidate, ">") || break
                push!(quoted, strip(candidate[2:end]))
                i += 1
            end
            push!(parts, "<div class='callout'><p>" * esc_html(join(quoted, " ")) * "</p></div>")
            continue
        else
            push!(paragraph, line)
        end
        i += 1
    end
    flush_paragraph!()
    return isempty(parts) ? "<p class='muted'>not recorded</p>" : join(parts, "")
end

function canonical_section_field(title)
    text = strip(String(title))
    low = lowercase(text)
    if occursin("目的", text)
        return "goal"
    elseif occursin("狀態與轉移", text)
        return "transition_summary"
    elseif occursin("特徵", text)
        return "feature_summary"
    elseif occursin("reward", low)
        return "reward_summary"
    elseif occursin("為什麼", text)
        return "why_promising"
    elseif occursin("測的是什麼", text)
        return "what_it_tests"
    elseif occursin("目前預期", text)
        return "expected_behavior"
    else
        return nothing
    end
end

function parse_example_sections(path)
    isfile(path) || return Dict{String,Dict{String,String}}()
    sections = Dict{String,Dict{String,String}}()
    lines = split(normalize_text(read(path, String)), '\n')
    current_env = nothing
    current_field = nothing
    buffer = String[]
    function flush!()
        if current_env === nothing || current_field === nothing
            empty!(buffer)
            return
        end
        text = strip(join(buffer, "\n"))
        if !isempty(text)
            entry = get!(sections, current_env) do
                Dict{String,String}()
            end
            entry[current_field] = text
        end
        empty!(buffer)
    end
    for line in lines
        stripped = strip(line)
        env_match = match(r"^#\s*(E\d+)[：:]\s*(.+)$", stripped)
        if env_match !== nothing
            flush!()
            current_env = env_match.captures[1]
            current_field = nothing
            entry = get!(sections, current_env) do
                Dict{String,String}()
            end
            entry["display_name"] = strip(env_match.captures[2])
            continue
        end
        if current_env !== nothing && occursin(r"^#\s+", stripped)
            flush!()
            current_env = nothing
            current_field = nothing
            continue
        end
        if current_env !== nothing
            heading_match = match(r"^##\s*(.+?)\s*$", stripped)
            if heading_match !== nothing
                flush!()
                current_field = canonical_section_field(heading_match.captures[1])
                continue
            end
            current_field === nothing || push!(buffer, line)
        end
    end
    flush!()
    return sections
end

function merge_example_sections!(catalog, sections)
    for (env, fields) in sections
        inst = haskey(catalog, env) ? catalog[env] : copy(catalog["unknown"])
        inst["env_id"] = env
        if haskey(fields, "display_name") && !isempty(strip(fields["display_name"]))
            inst["display_name"] = strip(fields["display_name"])
        end
        for key in ("goal", "transition_summary", "feature_summary", "reward_summary", "why_promising", "what_it_tests", "expected_behavior")
            if haskey(fields, key) && !isempty(strip(fields[key]))
                inst[key] = strip(fields[key])
            end
        end
        inst["source"] = "example.md"
        catalog[env] = inst
    end
end

function build_instance_catalog(repo_root)
    catalog = builtin_instance_catalog()
    merge_example_sections!(catalog, parse_example_sections(joinpath(repo_root, "example.md")))
    return catalog
end

function instance_for_env(catalog, env)
    if haskey(catalog, env)
        return catalog[env]
    end
    inst = copy(catalog["unknown"])
    inst["env_id"] = env
    inst["mechanism_tag"] = env
    return inst
end

function instance_title(inst)
    env = String(inst["env_id"])
    name = strip(String(inst["display_name"]))
    return isempty(name) ? env : string(env, " | ", name)
end

function ordered_keys(keys_vec, preferred)
    out = String[]
    seen = Set{String}()
    for key in preferred
        s = String(key)
        if s in keys_vec && !(s in seen)
            push!(out, s)
            push!(seen, s)
        end
    end
    for key in sort(String.(keys_vec))
        if !(key in seen)
            push!(out, key)
            push!(seen, key)
        end
    end
    return out
end

function case_param_pairs(group, inst)
    meta = group["meta"]
    ordered = ordered_keys(collect(Base.keys(meta)), inst["primary_knobs"])
    return [(key, String(meta[key])) for key in ordered]
end

function case_param_text(group, inst; sep=" | ")
    parts = [string(key, "=", value) for (key, value) in case_param_pairs(group, inst)]
    return join(parts, sep)
end

function active_knobs(groups, inst)
    knob_names = String[]
    for group in groups
        append!(knob_names, String.(collect(Base.keys(group["meta"]))))
    end
    knob_names = unique(knob_names)
    return isempty(knob_names) ? collect(String.(inst["primary_knobs"])) : ordered_keys(knob_names, inst["primary_knobs"])
end

function code_badges(items)
    clean = [strip(String(item)) for item in items if !isempty(strip(String(item)))]
    isempty(clean) && return "<span class='muted'>none</span>"
    return join(["<span class='badge badge-plain'><code>" * esc_html(item) * "</code></span>" for item in clean], " ")
end

function preview_values(values; max_items=8)
    uniq = sort(unique(String.(values)))
    isempty(uniq) && return "not recorded"
    if length(uniq) <= max_items
        return join(uniq, ", ")
    end
    return string(join(first(uniq, max_items), ", "), ", … (", length(uniq), " values)")
end

function case_display_label(group, inst)
    params = case_param_text(group, inst)
    title = instance_title(inst)
    return isempty(params) ? title : string(title, " | ", params)
end

function case_summary(group, inst)
    params = case_param_text(group, inst; sep=", ")
    focus = excerpt(get(inst, "what_it_tests", ""); limit=180)
    if focus == "not recorded"
        focus = excerpt(get(inst, "goal", ""); limit=180)
    end
    if isempty(params)
        return focus == "not recorded" ? "This case uses the recorded fixed parameters for this TD instance." : focus
    end
    if focus == "not recorded"
        return string("Case parameters: ", params, ".")
    end
    return string("Case parameters: ", params, ". ", focus)
end

function enrich_groups!(groups, catalog)
    for group in groups
        inst = instance_for_env(catalog, String(group["env"]))
        group["instance"] = inst
        group["mechanism_group_key"] = inst["mechanism_group_key"]
        group["mechanism_group"] = inst["mechanism_group"]
        group["mechanism_tag"] = inst["mechanism_tag"]
        group["display_label"] = case_display_label(group, inst)
        group["case_summary"] = case_summary(group, inst)
        group["search_blob"] = lowercase(join(filter(!isempty, [group["display_label"], group["case_summary"], case_param_text(group, inst; sep=" "), collapse_text(inst["goal"]), collapse_text(inst["what_it_tests"])]), " "))
    end
    return groups
end

primary_env_for_groups(groups) = begin
    envs = sort(unique(String[group["env"] for group in groups]))
    length(envs) == 1 ? first(envs) : "unknown"
end

function brief_block_html(title, text)
    body = strip(collapse_text(text))
    isempty(body) && return ""
    return "<div class='brief-block'><h3>" * esc_html(title) * "</h3>" * render_markdownish(text) * "</div>"
end

function default_reading_guide(inst)
    guide = strip(String(inst["reading_guide"]))
    !isempty(guide) && return guide
    key = String(inst["mechanism_group_key"])
    if key == "A"
        return "先看 final / best curves 有沒有一致往上抬，再看 learning curves 是短 transient 還是整段 pathwise amplification。這一類的核心問題是：幾何 switching 本身夠不夠強。"
    elseif key == "B"
        return "先看 divergence by c 和 reward / mixing 參數是否一起上升，再看 learning curves 是否呈現長時間偏置或 persistent excursion。這一類的核心問題是：慢 mixing forcing 能不能長時間把 iterate 拉遠。"
    elseif key == "C"
        return "把這些圖當作 barrier check。若多數 case 仍只出現有限 transient，代表你找到的是一個真實障礙，而不是單純實作不夠仔細。"
    else
        return "先看 Batch Parameters、Parameter Regime Summary 與 Case Interpretation Table，確認這個 run 究竟掃了哪些軸；再用 global / case plots 判斷哪些參數區間最不穩定。"
    end
end

function instance_brief_html(inst, groups)
    blocks = String[]
    push!(blocks, brief_block_html("Core idea", inst["goal"]))
    push!(blocks, brief_block_html("What it tests", inst["what_it_tests"]))
    push!(blocks, brief_block_html("State / transition", inst["transition_summary"]))
    push!(blocks, brief_block_html("Features", inst["feature_summary"]))
    push!(blocks, brief_block_html("Reward", inst["reward_summary"]))
    push!(blocks, brief_block_html("Why it looked promising", inst["why_promising"]))
    push!(blocks, brief_block_html("Expected behavior", inst["expected_behavior"]))
    push!(blocks, "<div class='brief-block'><h3>Key knobs</h3><div class='badge-row'>" * code_badges(active_knobs(groups, inst)) * "</div></div>")
    extra_roles = String.(get(inst, "extra_roles", String[]))
    role_html = isempty(extra_roles) ? "" : "<div class='badge-row'><span class='badge'>diagnostic roles</span>" * code_badges(extra_roles) * "</div>"
    return "<section class='section'><h2>TD Instance Brief</h2><article class='note-card instance-brief'><div class='top-links'><span class='pill'>Instance: <strong>" * esc_html(instance_title(inst)) * "</strong></span><span class='pill'>Category: <strong>" * esc_html(inst["mechanism_group"]) * "</strong></span><span class='pill'>Tag: <strong>" * esc_html(inst["mechanism_tag"]) * "</strong></span><span class='pill'>Doc source: <strong>" * esc_html(inst["source"]) * "</strong></span></div>" * role_html * "<p class='subtle'>這個區塊直接解釋目前這個 TD instance 在測什麼，讓你在看圖之前先知道它的機制與預期行為。</p><div class='brief-grid'>" * join(blocks, "") * "</div></article></section>"
end

function parameter_regime_rows_html(groups, inst)
    axes = Dict{String,Vector{String}}()
    for group in groups
        for (key, value) in group["meta"]
            push!(get!(axes, String(key), String[]), String(value))
        end
    end
    isempty(axes) && return "<tr><td colspan='4' class='muted'>No per-case metadata recorded.</td></tr>"
    rows = String[]
    for key in ordered_keys(collect(keys(axes)), active_knobs(groups, inst))
        values = sort(unique(filter(!isempty, axes[key])))
        variability = length(values) > 1 ? "varying" : "fixed"
        push!(rows, "<tr><td><code>" * esc_html(key) * "</code></td><td>" * esc_html(variability) * "</td><td><code>" * esc_html(preview_values(values)) * "</code></td><td>" * string(length(values)) * "</td></tr>")
    end
    return join(rows, "")
end

function case_interpretation_rows_html(groups)
    rows = String[]
    for group in groups
        stats = String[]
        isfinite(group["lambda"]) && push!(stats, "lambda=" * fmt_num(group["lambda"]))
        isfinite(group["kappa"]) && push!(stats, "kappa=" * fmt_num(group["kappa"]))
        isfinite(group["gamma"]) && push!(stats, "gamma=" * fmt_num(group["gamma"]))
        stat_html = isempty(stats) ? "<span class='muted'>not recorded</span>" : "<code>" * esc_html(join(stats, " | ")) * "</code>"
        push!(rows, "<tr><td><code>" * esc_html(group["case_id"]) * "</code></td><td><strong>" * esc_html(get(group, "display_label", group["label"])) * "</strong><div class='muted tiny'>" * esc_html(get(group, "case_summary", "")) * "</div></td><td><code>" * esc_html(join(fmt_short.(group["c"]), ", ")) * "</code></td><td>" * badges(group["meta"]) * "</td><td>" * stat_html * "</td></tr>")
    end
    return isempty(rows) ? "<tr><td colspan='5' class='muted'>No case metadata found.</td></tr>" : join(rows, "")
end

const REPORT_STYLE_EXTRA = raw"""<style>.instance-brief{padding:18px 20px}.brief-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:16px}.brief-block{padding:16px;border-radius:18px;border:1px solid var(--line);background:#fffaf4}.brief-block h3{margin:0 0 10px;font-size:1rem}.mini-table table{font-size:.88rem}.mini-table th,.mini-table td{padding:8px 10px}.instance-note{margin-top:10px}</style>"""
const INDEX_STYLE_EXTRA = raw"""<style>.group-section{margin-top:30px}.group-header{margin-bottom:14px;padding:18px;border-radius:22px;border:1px solid var(--line);background:#fff8f0;box-shadow:var(--shadow)}.group-header h2{margin:0 0 .35rem}.group-header p{margin:0;color:var(--muted)}.env-stack{display:grid;grid-template-columns:1fr;gap:18px}.env-card{padding:18px;border-radius:24px;border:1px solid var(--line);background:var(--card);box-shadow:var(--shadow)}.env-top{display:flex;justify-content:space-between;gap:16px;align-items:flex-start;flex-wrap:wrap}.env-top h2{margin:0 0 .2rem;font-size:1.35rem}.env-brief{margin:0;color:var(--muted)}.env-summary-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:10px;margin-top:14px}.env-summary-grid .cell{padding:10px;border-radius:16px;background:#fcf7ef;border:1px solid #eadccc}.env-summary-grid .k{display:block;color:var(--muted);font-size:.78rem}.env-summary-grid .v{display:block;margin-top:5px;font-size:1rem;font-weight:700}.env-latest{margin-top:14px}.env-latest h3{margin:0 0 10px;font-size:1rem}.run-list{margin-top:16px}.run-card h3{margin:.1rem 0 .25rem;font-size:1.05rem}</style>"""
function attach_plots(groups, assets, format)
    globals = Dict{String,Any}[]
    gallery = Dict{String,Any}[]
    unmatched = Dict{String,Any}[]
    by_slug = Dict{String,Dict{String,Any}}()
    by_id = Dict{String,Dict{String,Any}}()
    by_key = Dict{String,Dict{String,Any}}()
    for g in groups
        by_slug[lowercase(g["case_slug"])] = g
        by_id[String(g["case_id"])] = g
        haskey(g, "plot_key") && (by_key[g["plot_key"]] = g)
    end
    for base in sort(collect(keys(assets)))
        asset = assets[base]
        cls = classify_plot(base)
        src = !isempty(asset["png"]) ? asset["png"] : ""
        card = Dict{String,Any}(
            "base" => base,
            "src" => src,
            "png" => asset["png"],
            "eps" => asset["eps"],
            "warning" => isempty(src) && !isempty(asset["eps"]),
            "type" => cls.type,
            "obj" => cls.obj,
            "label" => cls.label,
            "case_id" => "global",
            "case_label" => cls.label,
            "case_summary" => "",
            "search" => lowercase(base),
            "c" => Float64[],
            "lambda" => NaN,
            "kappa" => NaN,
            "gamma" => NaN,
            "sort" => "9999-$(base)",
        )
        if cls.is_global
            push!(globals, card)
            continue
        end
        group = nothing
        if format == :manifest
            for (slug, g) in by_slug
                if occursin(slug, lowercase(base))
                    group = g
                    break
                end
            end
            if group === nothing
                m = match(r"case-(\d+)", lowercase(base))
                if m !== nothing
                    group = get(by_id, lpad(m.captures[1], 4, '0'), nothing)
                end
            end
        else
            key = legacy_plot_match(base)
            key !== nothing && (group = get(by_key, key, nothing))
        end
        if group === nothing
            push!(unmatched, card)
            continue
        end
        push!(group["plots"], !isempty(asset["png"]) ? asset["png"] : asset["eps"])
        card["case_id"] = String(group["case_id"])
        card["case_label"] = String(get(group, "display_label", group["label"]))
        card["case_summary"] = String(get(group, "case_summary", ""))
        card["search"] = lowercase(String(get(group, "search_blob", group["label"])) * " " * base)
        card["c"] = Vector{Float64}(group["c"])
        card["lambda"] = group["lambda"]
        card["kappa"] = group["kappa"]
        card["gamma"] = group["gamma"]
        card["sort"] = string(group["case_id"], "-", cls.type, "-", base)
        push!(gallery, card)
    end
    sort!(globals, by = c -> c["type"])
    sort!(gallery, by = c -> c["sort"])
    sort!(unmatched, by = c -> c["base"])
    return globals, gallery, unmatched
end

function plot_card(card, run_dir)
    img = !isempty(card["src"]) ? "<img loading='lazy' src='$(url_path(relpath(card["src"], run_dir)))' alt='$(esc_html(card["base"]))'>" : "<div class='image-warning'>PNG unavailable for inline display.</div>"
    links = String[]
    !isempty(card["png"]) && push!(links, "<a href='$(url_path(relpath(card["png"], run_dir)))'>PNG</a>")
    !isempty(card["eps"]) && push!(links, "<a href='$(url_path(relpath(card["eps"], run_dir)))'>EPS</a>")
    cset = isempty(card["c"]) ? "" : join(fmt_short.(sort(unique(card["c"]))), "|")
    info = ["<span class='badge'><code>$(esc_html(card["label"]))</code></span>"]
    if card["case_id"] != "global"
        push!(info, "<span class='badge'><code>case=$(esc_html(card["case_id"]))</code></span>")
        !isempty(card["c"]) && push!(info, "<span class='badge'><code>c ∈ $(esc_html(join(fmt_short.(sort(unique(card["c"]))), ", ")))</code></span>")
        isfinite(card["lambda"]) && push!(info, "<span class='badge'><code>lambda=$(esc_html(fmt_num(card["lambda"])))</code></span>")
        isfinite(card["kappa"]) && push!(info, "<span class='badge'><code>kappa=$(esc_html(fmt_num(card["kappa"])))</code></span>")
        isfinite(card["gamma"]) && push!(info, "<span class='badge'><code>gamma=$(esc_html(fmt_num(card["gamma"])))</code></span>")
    end
    warn = card["warning"] ? "<div class='callout warn'>PNG missing. This card keeps the original EPS link, but browsers may not render EPS inline.</div>" : ""
    summary = isempty(strip(String(get(card, "case_summary", "")))) ? "" : "<p class='muted tiny'>$(esc_html(String(card["case_summary"])))</p>"
    return "<article class='plot-card' data-gallery-card='1' data-search='$(esc_html(card["search"]))' data-plot-type='$(esc_html(card["type"]))' data-case-id='$(esc_html(card["case_id"]))' data-objective='$(esc_html(card["obj"]))' data-c-values='$(esc_html(cset))'><div class='plot-head'><h3>$(esc_html(card["case_label"]))</h3><div class='plot-file'><code>$(esc_html(card["base"]))</code></div></div>$(summary)<div class='badge-row'>$(join(info, " "))</div>$(warn)$(img)<div class='plot-links'>$(isempty(links) ? "<span class='muted'>no file links</span>" : join(links, " · "))</div></article>"
end

function parameter_table(groups, run_dir)
    rows = String[]
    for g in groups
        agg = [g["agg"][c] for c in sort(collect(keys(g["agg"]))) if isfile(g["agg"][c])]
        run = [g["run"][c] for c in sort(collect(keys(g["run"]))) if isfile(g["run"][c])]
        ratio = filter(isfile, String[g["ratio"]...])
        push!(rows, "<tr><td><code>$(esc_html(g["case_id"]))</code></td><td>$(esc_html(g["env"]))</td><td>$(esc_html(get(g, "display_label", g["label"])))</td><td><code>$(esc_html(join(fmt_short.(g["c"]), ", ")))</code></td><td><code>$(esc_html(fmt_num(g["lambda"])))</code></td><td><code>$(esc_html(fmt_num(g["kappa"])))</code></td><td><code>$(esc_html(fmt_num(g["gamma"])))</code></td><td><code>$(esc_html(fmt_num(g["theta_star"])))</code></td><td>$(badges(g["meta"]))</td><td>$(file_links(agg, run_dir))</td><td>$(file_links(run, run_dir))</td><td>$(file_links(ratio, run_dir))</td></tr>")
    end
    return join(rows, "")
end

function inventory_table(groups, run_dir)
    rows = String[]
    for g in groups
        agg = [g["agg"][c] for c in sort(collect(keys(g["agg"]))) if isfile(g["agg"][c])]
        run = [g["run"][c] for c in sort(collect(keys(g["run"]))) if isfile(g["run"][c])]
        ratio = filter(isfile, String[g["ratio"]...])
        plots = filter(isfile, String[g["plots"]...])
        push!(rows, "<tr><td><code>$(esc_html(g["case_id"]))</code></td><td>$(esc_html(get(g, "display_label", g["label"])))</td><td>$(file_links(agg, run_dir))</td><td>$(file_links(run, run_dir))</td><td>$(file_links(ratio, run_dir))</td><td>$(file_links(plots, run_dir))</td></tr>")
    end
    return join(rows, "")
end

compact_divergence_table(rows) = isempty(rows) ? "<p class='muted'>No run CSVs found.</p>" : "<div class='table-wrap mini-table'><table><thead><tr><th>c</th><th>rate</th></tr></thead><tbody>" * join(["<tr><td><code>" * esc_html(fmt_short(row["c"])) * "</code></td><td>" * esc_html(fmt_num(row["rate"])) * "</td></tr>" for row in rows], "") * "</tbody></table></div>"
plot_status(plot_count, png_complete) = plot_count == 0 ? "none" : png_complete ? "complete" : "partial"
plot_status_rank(status) = status == "complete" ? 2 : status == "partial" ? 1 : 0
plot_status_label(status, png_count, plot_count) = status == "none" ? "no plots" : status == "complete" ? "PNG complete" : string("PNG ", png_count, "/", plot_count)

function run_card_html(summary, root)
    report_rel = url_path(relpath(summary["report_path"], root))
    search = lowercase(join([summary["run_label"], summary["rel_dir"], summary["primary_env"], summary["instance_title"], summary["instance_one_liner"], summary["mechanism_tag"]], " "))
    date_val = summary["last_modified"] === nothing ? 0 : Dates.value(summary["last_modified"])
    status = summary["png_status"]
    return "<article class='run-card' data-run-card='1' data-search='" * esc_html(search) * "' data-env='" * esc_html(summary["primary_env"]) * "' data-manifest='" * (summary["manifest"] ? "manifest" : "legacy") * "' data-png-status='" * esc_html(status) * "' data-date='" * string(date_val) * "' data-name='" * esc_html(lowercase(summary["run_label"])) * "' data-png-rank='" * string(plot_status_rank(status)) * "'><div class='path'><code>" * esc_html(summary["rel_dir"]) * "</code></div><h3>" * esc_html(summary["run_label"]) * "</h3><p class='muted tiny'>" * esc_html(summary["instance_one_liner"]) * "</p><div class='meta'><span class='badge'>" * esc_html(plot_status_label(status, summary["png_count"], summary["plot_count"])) * "</span>" * (summary["manifest"] ? "<span class='badge'>manifest</span>" : "<span class='badge'>legacy</span>") * (summary["log"] ? "<span class='badge'>log</span>" : "<span class='badge'>no log</span>") * "</div><div class='run-metrics'><div class='cell'><span class='k'>cases</span><span class='v'>" * string(summary["case_count"]) * "</span></div><div class='cell'><span class='k'>c count</span><span class='v'>" * string(summary["c_count"]) * "</span></div><div class='cell'><span class='k'>n_runs</span><span class='v'>" * (summary["n_runs"] === nothing ? "not recorded" : string(summary["n_runs"])) * "</span></div><div class='cell'><span class='k'>n_steps</span><span class='v'>" * (summary["n_steps"] === nothing ? "not recorded" : string(summary["n_steps"])) * "</span></div><div class='cell'><span class='k'>threads</span><span class='v'>" * (summary["threads"] === nothing ? "not recorded" : string(summary["threads"])) * "</span></div><div class='cell'><span class='k'>plots</span><span class='v'>" * string(summary["plot_count"]) * "</span></div></div><p class='muted tiny'>modified: " * esc_html(fmt_dt(summary["last_modified"])) * "</p><p><a href='" * report_rel * "'>Open report</a></p></article>"
end

function env_card_html(env_id, runs, root)
    latest = first(runs)
    latest_link = url_path(relpath(latest["report_path"], root))
    env_search = lowercase(join([latest["instance_title"], latest["instance_one_liner"], latest["mechanism_tag"], env_id], " "))
    html = IOBuffer()
    print(html, "<article class='env-card' data-env-card='1' data-group='", esc_html(latest["mechanism_group_key"]), "' data-env='", esc_html(env_id), "' data-search='", esc_html(env_search), "' data-env-name='", esc_html(lowercase(latest["instance_title"])), "' data-latest-date='", latest["last_modified"] === nothing ? 0 : Dates.value(latest["last_modified"]), "' data-png-rank='", plot_status_rank(latest["png_status"]), "'><div class='env-top'><div><h2>", esc_html(latest["instance_title"]), "</h2><p class='env-brief'>", esc_html(latest["instance_one_liner"]), "</p></div><p><a href='", latest_link, "'>Open latest report</a></p></div><div class='meta'><span class='badge'>", esc_html(latest["mechanism_tag"]), "</span><span class='badge'>runs: ", length(runs), "</span><span class='badge'>latest plots: ", latest["plot_count"], "</span><span class='badge'>latest updated: ", esc_html(fmt_dt(latest["last_modified"])), "</span></div><div class='env-summary-grid'><div class='cell'><span class='k'>Latest run</span><span class='v'>", esc_html(latest["run_label"]), "</span></div><div class='cell'><span class='k'>Observed runs</span><span class='v'>", length(runs), "</span></div><div class='cell'><span class='k'>Latest PNG status</span><span class='v'>", esc_html(plot_status_label(latest["png_status"], latest["png_count"], latest["plot_count"])), "</span></div><div class='cell'><span class='k'>Latest c grid</span><span class='v'>", latest["c_count"], "</span></div></div><div class='env-latest'><h3>Latest divergence by c</h3>", compact_divergence_table(latest["divergence_rows"]), "</div><div class='run-grid run-list'>")
    for run in runs
        print(html, run_card_html(run, root))
    end
    print(html, "</div></article>")
    return String(take!(html))
end
function build_run_report(run_dir, root, catalog)
    format = isfile(joinpath(run_dir, "manifest.tsv")) ? :manifest : :legacy
    warn = String[]
    png = ensure_pngs(run_dir)
    png.attempted && push!(warn, png.ok ? "PNG export completed for missing images." : "PNG export incomplete: $(png.msg)")
    groups = format == :manifest ? build_manifest_groups(run_dir) : build_legacy_groups(run_dir)
    enrich_groups!(groups, catalog)
    assets = plot_assets(run_dir)
    globals, gallery, unmatched = attach_plots(groups, assets, format)
    isempty(assets) && push!(warn, "No plot images were found under plots/. This usually means upstream plotting failed for this run; CSV files and parameters are still indexed here.")
    !isempty(unmatched) && push!(warn, "$(length(unmatched)) plot(s) could not be matched to a case and are listed separately.")
    envs = sort(unique([String(g["env"]) for g in groups]))
    primary_env = primary_env_for_groups(groups)
    run_instance = instance_for_env(catalog, primary_env)
    all_c_lists = [Vector{Float64}(g["c"]) for g in groups]
    c_grid = isempty(all_c_lists) ? Float64[] : sort(unique(vcat(all_c_lists...)))
    sample_run = nothing
    for g in groups
        for p in values(g["run"])
            if isfile(p)
                sample_run = p
                break
            end
        end
        sample_run === nothing || break
    end
    n_runs = sample_run === nothing ? nothing : csv_rows(sample_run)
    n_steps = infer_n_steps(run_dir)
    log_meta = log_info(guess_log(run_dir))
    threads = get(log_meta, "threads", nothing)
    last_mod = mtime_dt(run_dir)
    generated = Dates.now()
    entries = safe_readdir(run_dir)
    csv_count = count(name -> endswith(lowercase(name), ".csv"), entries)
    tsv_count = count(name -> endswith(lowercase(name), ".tsv"), entries)
    png_count = count(a -> !isempty(a["png"]), values(assets))
    missing_png = count(a -> !isempty(a["eps"]) && isempty(a["png"]), values(assets))
    plot_count = length(assets)
    png_complete = plot_count > 0 && missing_png == 0
    png_status = plot_status(plot_count, png_complete)
    div_rows = divergence_rows(groups)
    met_rows = metric_rows(groups)
    params = [
        ("instance", instance_title(run_instance), run_instance["source"]),
        ("category", String(run_instance["mechanism_group"]), "instance catalog"),
        ("n_steps", n_steps === nothing ? "not recorded" : string(n_steps), n_steps === nothing ? "not recorded" : "filename inference"),
        ("n_runs", n_runs === nothing ? "not recorded" : string(n_runs), n_runs === nothing ? "not recorded" : "run csv"),
        ("threads", threads === nothing ? "not recorded" : string(threads), threads === nothing ? "not recorded" : "log"),
        ("c grid", isempty(c_grid) ? "not recorded" : join(fmt_short.(c_grid), ", "), format == :manifest ? "manifest" : "filename inference"),
        ("case count", string(length(groups)), format == :manifest ? "manifest" : "filename inference"),
        ("plot assets", string(length(assets)), "plots directory"),
        ("CSV count", string(csv_count), "filesystem"),
        ("TSV count", string(tsv_count), "filesystem"),
        ("manifest", isfile(joinpath(run_dir, "manifest.tsv")) ? "present" : "absent", "filesystem"),
        ("log", guess_log(run_dir) === nothing ? "absent" : basename(guess_log(run_dir)), guess_log(run_dir) === nothing ? "filesystem" : "log discovery"),
    ]
    report_path = joinpath(run_dir, "report.html")
    case_ids = sort(unique([String(c["case_id"]) for c in gallery if c["case_id"] != "global"]))
    plot_types = sort(unique([String(c["type"]) for c in gallery]))
    objectives = sort(unique([String(c["obj"]) for c in gallery]))
    open(report_path, "w") do io
        print(io, "<!doctype html><html lang='zh-Hant'><head><meta charset='utf-8'><meta name='viewport' content='width=device-width, initial-scale=1'><title>", esc_html(basename(run_dir)), " | TD Runs Report</title>", REPORT_STYLE, REPORT_STYLE_EXTRA, "</head><body><div class='page'>")
        print(io, "<section class='hero'><div class='hero-top'><div><div class='top-links'><a class='pill' href='", url_path(relpath(joinpath(root, "index.html"), run_dir)), "'>Back to index</a><span class='pill'><code>", esc_html(relpath(run_dir, root)), "</code></span><span class='pill'>", esc_html(run_instance["mechanism_group"]), "</span><span class='pill'>", esc_html(run_instance["mechanism_tag"]), "</span></div><h1>", esc_html(basename(run_dir)), "</h1><p class='subtle'>", esc_html(instance_title(run_instance)), "。", esc_html(excerpt(run_instance["what_it_tests"]; limit=220)), "</p></div><div>")
        for env in first(envs, min(length(envs), MAX_ENV_BADGES))
            print(io, "<span class='pill'>env: <strong>", esc_html(env), "</strong></span>")
        end
        print(io, "</div></div><div class='hero-grid'><div class='hero-stat'><span class='label'>Cases</span><span class='value'>", length(groups), "</span></div><div class='hero-stat'><span class='label'>c values</span><span class='value'>", length(c_grid), "</span></div><div class='hero-stat'><span class='label'>Plot assets</span><span class='value'>", plot_count, "</span></div><div class='hero-stat'><span class='label'>PNG completeness</span><span class='value'>", plot_status_label(png_status, png_count, plot_count), "</span></div><div class='hero-stat'><span class='label'>Generated at</span><span class='value tiny'>", esc_html(fmt_dt(generated)), "</span></div><div class='hero-stat'><span class='label'>Run modified</span><span class='value tiny'>", esc_html(fmt_dt(last_mod)), "</span></div></div>")
        for msg in warn
            print(io, "<div class='callout warn'>", esc_html(msg), "</div>")
        end
        print(io, "</section>")
        print(io, instance_brief_html(run_instance, groups))
        print(io, "<section class='section'><h2>Batch Parameters</h2><div class='table-wrap'><table><thead><tr><th>Parameter</th><th>Value</th><th>Source</th></tr></thead><tbody>")
        for (label, value, source) in params
            print(io, "<tr><td>", esc_html(label), "</td><td><code>", esc_html(value), "</code></td><td>", esc_html(source), "</td></tr>")
        end
        print(io, "</tbody></table></div></section>")
        print(io, "<section class='section'><h2>Result Summary</h2><div class='summary-cards'><article class='note-card'><h3>Divergence by c for this instance</h3><div class='table-wrap'><table><thead><tr><th>c</th><th>total runs</th><th>diverged</th><th>rate</th></tr></thead><tbody>")
        if isempty(div_rows)
            print(io, "<tr><td colspan='4' class='muted'>No run CSVs found.</td></tr>")
        else
            for row in div_rows
                print(io, "<tr><td><code>", esc_html(fmt_short(row["c"])), "</code></td><td>", row["total"], "</td><td>", row["diverged"], "</td><td>", esc_html(fmt_num(row["rate"])), "</td></tr>")
            end
        end
        print(io, "</tbody></table></div></article><article class='note-card'><h3>Plot Families</h3><div class='table-wrap'><table><thead><tr><th>family</th><th>count</th></tr></thead><tbody>", family_rows(vcat(globals, gallery, unmatched)), "</tbody></table></div></article><article class='note-card'><h3>Last Aggregated Row Metrics</h3><div class='table-wrap'><table><thead><tr><th>metric</th><th>min</th><th>median</th><th>max</th></tr></thead><tbody>")
        for row in met_rows
            print(io, "<tr><td>", esc_html(row["label"]), "</td><td><code>", esc_html(fmt_num(row["min"])), "</code></td><td><code>", esc_html(fmt_num(row["median"])), "</code></td><td><code>", esc_html(fmt_num(row["max"])), "</code></td></tr>")
        end
        print(io, "</tbody></table></div></article></div></section>")
        print(io, "<section class='section'><h2>Parameter Regime Summary</h2><div class='table-wrap'><table><thead><tr><th>axis</th><th>mode</th><th>values</th><th>distinct count</th></tr></thead><tbody>", parameter_regime_rows_html(groups, run_instance), "</tbody></table></div></section>")
        print(io, "<section class='section'><h2>How to Read This Run</h2><article class='note-card'>", render_markdownish(default_reading_guide(run_instance)), "</article></section>")
        print(io, "<section class='section'><h2>Case Interpretation Table</h2><div class='table-wrap'><table><thead><tr><th>case_id</th><th>interpretation</th><th>c values</th><th>metadata</th><th>spectral stats</th></tr></thead><tbody>", case_interpretation_rows_html(groups), "</tbody></table></div></section>")
        print(io, "<section class='section'><h2>Global Plots</h2><div class='grid-2'>")
        isempty(globals) ? print(io, "<article class='note-card muted'>No global plots found for this run.</article>") : foreach(c -> print(io, global_card(c, run_dir)), globals)
        print(io, "</div></section>")
        print(io, "<section class='section'><h2>Case Gallery</h2><div class='filters'><div class='filter-grid'><label>Search<input id='gallery-search' type='search' placeholder='case label, file name, metadata'></label><label>Plot type<select id='gallery-plot-type'><option value='all'>show all</option>")
        for v in plot_types
            print(io, "<option value='", esc_html(v), "'>", esc_html(v), "</option>")
        end
        print(io, "</select></label><label>Case id<select id='gallery-case-id'><option value='all'>show all</option>")
        for v in case_ids
            print(io, "<option value='", esc_html(v), "'>", esc_html(v), "</option>")
        end
        print(io, "</select></label><label>c value<select id='gallery-c'><option value='all'>show all</option>")
        for v in c_grid
            text = fmt_short(v)
            print(io, "<option value='", esc_html(text), "'>", esc_html(text), "</option>")
        end
        print(io, "</select></label><label>Objective<select id='gallery-objective'><option value='all'>show all</option>")
        for v in objectives
            print(io, "<option value='", esc_html(v), "'>", esc_html(v), "</option>")
        end
        print(io, "</select></label></div><p class='subtle tiny'>Visible cards: <span id='gallery-count'>0</span></p></div><div class='gallery'>")
        isempty(gallery) ? print(io, "<article class='note-card muted'>No case-level plots found.</article>") : foreach(c -> print(io, plot_card(c, run_dir)), gallery)
        print(io, "</div>")
        if !isempty(unmatched)
            print(io, "<div class='unmatched'><h3>Unmatched Plots</h3><div class='grid-2'>")
            foreach(c -> print(io, plot_card(c, run_dir)), unmatched)
            print(io, "</div></div>")
        end
        print(io, "</section><section class='section'><h2>Detailed Parameters</h2><div class='table-wrap'><table><thead><tr><th>case_id</th><th>env</th><th>label</th><th>c values</th><th>lambda_min</th><th>kappa</th><th>gamma</th><th>theta* norm</th><th>metadata</th><th>agg CSV</th><th>run CSV</th><th>ratio files</th></tr></thead><tbody>", parameter_table(groups, run_dir), "</tbody></table></div></section><section class='section'><h2>File Inventory</h2><div class='table-wrap'><table><thead><tr><th>case_id</th><th>label</th><th>agg CSV</th><th>run CSV</th><th>ratio</th><th>plots</th></tr></thead><tbody>", inventory_table(groups, run_dir), "</tbody></table></div></section>")
        print(io, "<script>const cards=[...document.querySelectorAll('[data-gallery-card=\"1\"]')];function applyGalleryFilters(){const q=(document.getElementById('gallery-search').value||'').toLowerCase();const plotType=document.getElementById('gallery-plot-type').value;const caseId=document.getElementById('gallery-case-id').value;const cValue=document.getElementById('gallery-c').value;const objective=document.getElementById('gallery-objective').value;let visible=0;for(const card of cards){const search=(card.dataset.search||'').toLowerCase();const plotOk=plotType==='all'||card.dataset.plotType===plotType;const caseOk=caseId==='all'||card.dataset.caseId===caseId;const objectiveOk=objective==='all'||card.dataset.objective===objective;const cSet=(card.dataset.cValues||'').split('|').filter(Boolean);const cOk=cValue==='all'||cSet.includes(cValue);const queryOk=!q||search.includes(q);const show=plotOk&&caseOk&&objectiveOk&&cOk&&queryOk;card.hidden=!show;if(show)visible++;}document.getElementById('gallery-count').textContent=(visible + ' / ' + cards.length);}['gallery-search','gallery-plot-type','gallery-case-id','gallery-c','gallery-objective'].forEach(id=>document.getElementById(id).addEventListener('input',applyGalleryFilters));applyGalleryFilters();</script></div></body></html>")
    end
    return Dict{String,Any}(
        "run_dir" => run_dir,
        "rel_dir" => relpath(run_dir, root),
        "run_label" => basename(run_dir),
        "envs" => envs,
        "primary_env" => primary_env,
        "instance_title" => instance_title(run_instance),
        "instance_one_liner" => excerpt(run_instance["goal"]; limit=140) == "not recorded" ? excerpt(run_instance["what_it_tests"]; limit=140) : excerpt(run_instance["goal"]; limit=140),
        "mechanism_group_key" => run_instance["mechanism_group_key"],
        "mechanism_group" => run_instance["mechanism_group"],
        "mechanism_tag" => run_instance["mechanism_tag"],
        "case_count" => length(groups),
        "c_count" => length(c_grid),
        "n_runs" => n_runs,
        "n_steps" => n_steps,
        "threads" => threads,
        "plot_count" => plot_count,
        "png_count" => png_count,
        "png_complete" => png_complete,
        "png_status" => png_status,
        "manifest" => isfile(joinpath(run_dir, "manifest.tsv")),
        "log" => guess_log(run_dir) !== nothing,
        "last_modified" => last_mod,
        "report_path" => report_path,
        "divergence_rows" => div_rows,
    )
end
function render_index(root, summaries, skipped)
    env_map = Dict{String,Vector{Dict{String,Any}}}()
    for summary in summaries
        push!(get!(env_map, String(summary["primary_env"]), Dict{String,Any}[]), summary)
    end
    for runs in values(env_map)
        sort!(runs, by = s -> s["last_modified"] === nothing ? DateTime(1900,1,1) : s["last_modified"], rev=true)
    end
    envs = sort(collect(keys(env_map)))
    open(joinpath(root, "index.html"), "w") do io
        print(io, "<!doctype html><html lang='zh-Hant'><head><meta charset='utf-8'><meta name='viewport' content='width=device-width, initial-scale=1'><title>TD Runs Viewer</title>", INDEX_STYLE, INDEX_STYLE_EXTRA, "</head><body><div class='page'><section class='hero'><h1>TD Runs Viewer</h1><p>Instance-aware static HTML index for local experiment browsing. Runs are grouped by TD mechanism so you can compare different instance families before drilling down into a specific report.</p><div class='hero-grid'><div class='stat'><span class='label'>Stable runs indexed</span><span class='value'>", length(summaries), "</span></div><div class='stat'><span class='label'>Distinct env cards</span><span class='value'>", length(envs), "</span></div><div class='stat'><span class='label'>PNG complete runs</span><span class='value'>", count(s -> s["png_status"] == "complete", summaries), "</span></div><div class='stat'><span class='label'>Skipped active runs</span><span class='value'>", length(skipped), "</span></div></div></section><section class='controls'><div class='control-grid'><label>Search<input id='run-search' type='search' placeholder='env, mechanism, run label'></label><label>Mechanism group<select id='run-group'><option value='all'>show all</option>")
        for key in GROUP_ORDER
            print(io, "<option value='", esc_html(key), "'>", esc_html(GROUP_INFO[key]["label"]), "</option>")
        end
        print(io, "</select></label><label>Env<select id='run-env'><option value='all'>show all</option>")
        for env in envs
            print(io, "<option value='", esc_html(env), "'>", esc_html(env), "</option>")
        end
        print(io, "</select></label><label>Manifest<select id='run-manifest'><option value='all'>show all</option><option value='manifest'>manifest only</option><option value='legacy'>legacy only</option></select></label><label>PNG status<select id='run-png'><option value='all'>show all</option><option value='complete'>PNG complete</option><option value='partial'>PNG partial</option><option value='none'>no plots</option></select></label><label>Sort<select id='run-sort'><option value='date-desc'>newest first</option><option value='date-asc'>oldest first</option><option value='env-asc'>env A→Z</option><option value='name-asc'>run name A→Z</option><option value='png-desc'>PNG complete first</option></select></label></div><p class='muted'>Visible env cards: <span id='env-count'>0</span> · Visible run cards: <span id='run-count'>0</span></p></section>")
        for key in GROUP_ORDER
            env_ids = [env for env in envs if first(env_map[env])["mechanism_group_key"] == key]
            isempty(env_ids) && continue
            print(io, "<section class='section group-section' data-group-section='", esc_html(key), "'><div class='group-header'><h2>", esc_html(GROUP_INFO[key]["label"]), "</h2><p>", esc_html(GROUP_INFO[key]["blurb"]), "</p></div><div class='env-stack'>")
            for env in env_ids
                print(io, env_card_html(env, env_map[env], root))
            end
            print(io, "</div></section>")
        end
        if !isempty(skipped)
            print(io, "<section class='section'><h2>Skipped Active Runs</h2><div class='note'><p>The following run directories were skipped because they changed within the last ", STABILITY_WINDOW_SECONDS, " seconds or their environment log has not finished yet. Re-run the generator after the batch completes.</p><ul>")
            for dir in skipped
                print(io, "<li><code>", esc_html(relpath(dir, root)), "</code></li>")
            end
            print(io, "</ul></div></section>")
        end
        print(io, "<script>const envCards=[...document.querySelectorAll('[data-env-card=\"1\"]')];const groupSections=[...document.querySelectorAll('[data-group-section]')];function compareNodes(a,b,sort){if(sort==='date-asc')return Number(a.dataset.latestDate||a.dataset.date)-Number(b.dataset.latestDate||b.dataset.date);if(sort==='env-asc')return (a.dataset.envName||a.dataset.env||'').localeCompare(b.dataset.envName||b.dataset.env||'')||(a.dataset.name||'').localeCompare(b.dataset.name||'');if(sort==='name-asc')return (a.dataset.name||a.dataset.envName||'').localeCompare(b.dataset.name||b.dataset.envName||'');if(sort==='png-desc')return Number(b.dataset.pngRank||0)-Number(a.dataset.pngRank||0)||Number(b.dataset.latestDate||b.dataset.date)-Number(a.dataset.latestDate||a.dataset.date);return Number(b.dataset.latestDate||b.dataset.date)-Number(a.dataset.latestDate||a.dataset.date);}function applyRunFilters(){const q=(document.getElementById('run-search').value||'').toLowerCase();const env=document.getElementById('run-env').value;const group=document.getElementById('run-group').value;const manifest=document.getElementById('run-manifest').value;const png=document.getElementById('run-png').value;const sort=document.getElementById('run-sort').value;let visibleEnvs=0;let visibleRuns=0;for(const envCard of envCards){const envMatch=!q||(envCard.dataset.search||'').toLowerCase().includes(q);const groupOk=group==='all'||envCard.dataset.group===group;const runCards=[...envCard.querySelectorAll('[data-run-card=\"1\"]')];const runList=envCard.querySelector('.run-list');const visible=[];for(const runCard of runCards){const runSearch=(runCard.dataset.search||'').toLowerCase();const show=groupOk&&(env==='all'||runCard.dataset.env===env)&&(manifest==='all'||runCard.dataset.manifest===manifest)&&(png==='all'||runCard.dataset.pngStatus===png)&&(!q||envMatch||runSearch.includes(q));runCard.hidden=!show;if(show){visible.push(runCard);visibleRuns++;}}visible.sort((a,b)=>compareNodes(a,b,sort));for(const card of visible){runList.appendChild(card);}envCard.hidden=visible.length===0;if(!envCard.hidden)visibleEnvs++;}for(const section of groupSections){const stack=section.querySelector('.env-stack');const visible=[...stack.querySelectorAll('[data-env-card=\"1\"]:not([hidden])')];visible.sort((a,b)=>compareNodes(a,b,sort));for(const card of visible){stack.appendChild(card);}section.hidden=visible.length===0;}document.getElementById('env-count').textContent=String(visibleEnvs);document.getElementById('run-count').textContent=String(visibleRuns);}['run-search','run-group','run-env','run-manifest','run-png','run-sort'].forEach(id=>document.getElementById(id).addEventListener('input',applyRunFilters));applyRunFilters();</script></div></body></html>")
    end
end

function main(args)
    root = parse_args(args)
    isdir(root) || error("Root directory not found: $(root)")
    stable, skipped = discover_runs(root)
    catalog = build_instance_catalog(dirname(root))
    summaries = Dict{String,Any}[]
    for run_dir in stable
        println("[report] ", relpath(run_dir, root))
        push!(summaries, build_run_report(run_dir, root, catalog))
    end
    sort!(summaries, by = s -> s["last_modified"] === nothing ? DateTime(1900,1,1) : s["last_modified"], rev=true)
    render_index(root, summaries, skipped)
    println("[done] index => ", joinpath(root, "index.html"))
end


function longpath(path)
    s = String(path)
    startswith(s, "\\?\\") && return s
    if startswith(s, "\\")
        return "\\?\\UNC\\" * s[3:end]
    end
    return "\\?\\" * abspath(s)
end

function safe_readdir(path)
    try
        return readdir(path)
    catch err
        return readdir(longpath(path))
    end
end

