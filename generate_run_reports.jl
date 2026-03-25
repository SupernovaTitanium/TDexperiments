#!/usr/bin/env julia

using Dates
using Printf
using Statistics

const STABILITY_WINDOW_SECONDS = 90
const MAX_ENV_BADGES = 6

function print_help()
    println("Usage: julia $(basename(@__FILE__)) --root td_divergence_logs")
end

function parse_args(args)
    root = nothing
    i = 1
    while i <= length(args)
        arg = args[i]
        if arg in ("-h", "--help")
            print_help()
            exit(0)
        elseif arg == "--root" && i < length(args)
            root = args[i + 1]
            i += 2
            continue
        else
            error("Unknown or incomplete argument: $(arg)")
        end
    end
    root === nothing && error("Missing required --root")
    return abspath(root)
end

esc_html(x) = replace(replace(replace(replace(replace(String(x), '&' => "&amp;"), '<' => "&lt;"), '>' => "&gt;"), '"' => "&quot;"), '\'' => "&#39;")

function url_path(path)
    text = replace(String(path), '\\' => '/')
    io = IOBuffer()
    for byte in codeunits(text)
        ch = Char(byte)
        if ('a' <= ch <= 'z') || ('A' <= ch <= 'Z') || ('0' <= ch <= '9') || ch in ('-', '_', '.', '~', '/')
            print(io, ch)
        else
            @printf(io, "%%%02X", byte)
        end
    end
    return String(take!(io))
end

function fmt_num(v; digits=3)
    v isa Number || return "not recorded"
    x = float(v)
    isfinite(x) || return "not recorded"
    if x == 0.0
        return "0"
    elseif abs(x) >= 1e3 || abs(x) < 1e-2
        return @sprintf("%.*e", digits, x)
    else
        return @sprintf("%.*f", digits, x)
    end
end

function fmt_short(v)
    v isa Number || return "not recorded"
    x = float(v)
    isfinite(x) || return "not recorded"
    return @sprintf("%.2e", x)
end

fmt_dt(dt::Union{Nothing,DateTime}) = dt === nothing ? "not recorded" : Dates.format(dt, dateformat"yyyy-mm-dd HH:MM:SS")

function parse_float(x)
    try
        return parse(Float64, String(x))
    catch
        return NaN
    end
end

function parse_int(x)
    try
        return parse(Int, String(x))
    catch
        return nothing
    end
end

function metadata_dict(blob)
    out = Dict{String,String}()
    for item in split(String(blob), ';')
        s = strip(item)
        isempty(s) && continue
        if occursin('=', s)
            a, b = split(s, '='; limit=2)
            out[strip(a)] = strip(b)
        else
            out[s] = "true"
        end
    end
    return out
end

function parse_table(path, delim)
    rows = Dict{String,String}[]
    open(path, "r") do io
        eof(io) && return rows
        header = split(chomp(readline(io)), delim; keepempty=true)
        for raw in eachline(io)
            line = chomp(raw)
            isempty(line) && continue
            vals = split(line, delim; keepempty=true)
            if length(vals) < length(header)
                append!(vals, fill("", length(header) - length(vals)))
            end
            row = Dict{String,String}()
            for i in eachindex(header)
                row[header[i]] = vals[i]
            end
            push!(rows, row)
        end
    end
    return rows
end

function csv_rows(path)
    n = 0
    open(path, "r") do io
        eof(io) && return 0
        readline(io)
        for line in eachline(io)
            isempty(strip(line)) || (n += 1)
        end
    end
    return n
end

function csv_last_row(path)
    header = String[]
    last = String[]
    open(path, "r") do io
        eof(io) && return Dict{String,String}()
        header = split(chomp(readline(io)), ','; keepempty=true)
        for raw in eachline(io)
            line = chomp(raw)
            isempty(line) && continue
            last = split(line, ','; keepempty=true)
        end
    end
    isempty(last) && return Dict{String,String}()
    if length(last) < length(header)
        append!(last, fill("", length(header) - length(last)))
    end
    row = Dict{String,String}()
    for i in eachindex(header)
        row[header[i]] = last[i]
    end
    return row
end

function run_stats(path)
    isfile(path) || return (n=0, d=0)
    open(path, "r") do io
        eof(io) && return (n=0, d=0)
        header = split(chomp(readline(io)), ','; keepempty=true)
        div_idx = something(findfirst(==("diverged"), header), 2)
        n = 0
        d = 0
        for raw in eachline(io)
            line = chomp(raw)
            isempty(line) && continue
            vals = split(line, ','; keepempty=true)
            n += 1
            if div_idx <= length(vals)
                try d += parse(Int, vals[div_idx]) catch end
            end
        end
        return (n=n, d=d)
    end
end

function parse_alpha(path)
    parts = split(splitext(basename(path))[1], "_")
    if length(parts) < 2 || parts[1] != "alpha"
        return (param=NaN, scale=NaN, eigen=NaN, kappa=NaN, case_id="", sched=false, runs=false)
    end
    param = try parse(Float64, parts[2]) catch; NaN end
    scale = NaN; eigen = NaN; kappa = NaN; case_id = ""; sched = false; runs = false
    i = 3
    while i <= length(parts)
        token = parts[i]
        if token == "runs"
            runs = true; i += 1
        elseif token == "sched" && i < length(parts) && parts[i + 1] == "theory"
            sched = true; i += 2
        elseif token in ("scale", "omega") && i < length(parts)
            scale = try parse(Float64, parts[i + 1]) catch; NaN end; i += 2
        elseif token == "eigen" && i < length(parts)
            eigen = try parse(Float64, parts[i + 1]) catch; NaN end; i += 2
        elseif token == "kappa" && i < length(parts)
            kappa = try parse(Float64, parts[i + 1]) catch; NaN end; i += 2
        elseif token == "case" && i < length(parts)
            case_id = parts[i + 1]; i += 2
        else
            i += 1
        end
    end
    return (param=param, scale=scale, eigen=eigen, kappa=kappa, case_id=case_id, sched=sched, runs=runs)
end

function find_runs_csv(path)
    meta = parse_alpha(path)
    dir = dirname(path)
    names = String[]
    if !isempty(meta.case_id)
        push!(names, @sprintf("alpha_%.2e_runs_sched_theory_case_%s.csv", meta.param, meta.case_id))
    end
    if meta.sched && isfinite(meta.scale) && isfinite(meta.eigen)
        if isfinite(meta.kappa)
            push!(names, @sprintf("alpha_%.2e_runs_sched_theory_scale_%.6e_eigen_%.2e_kappa_%.2e.csv", meta.param, meta.scale, meta.eigen, meta.kappa))
            push!(names, @sprintf("alpha_%.2e_runs_sched_theory_omega_%.6e_eigen_%.2e_kappa_%.2e.csv", meta.param, meta.scale, meta.eigen, meta.kappa))
        end
        push!(names, @sprintf("alpha_%.2e_runs_sched_theory_scale_%.6e_eigen_%.2e.csv", meta.param, meta.scale, meta.eigen))
        push!(names, @sprintf("alpha_%.2e_runs_sched_theory_omega_%.6e_eigen_%.2e.csv", meta.param, meta.scale, meta.eigen))
    end
    for name in names
        full = joinpath(dir, name)
        isfile(full) && return full
    end
    return ""
end

function log_info(path)
    info = Dict{String,Any}("exists" => false, "threads" => nothing, "done" => false)
    path === nothing && return info
    isfile(path) || return info
    info["exists"] = true
    open(path, "r") do io
        for raw in eachline(io)
            line = chomp(raw)
            if info["threads"] === nothing
                m = match(r"Using\s+(\d+)\s+threads", line)
                m !== nothing && (info["threads"] = parse(Int, m.captures[1]))
            end
            occursin("DONE", line) && (info["done"] = true)
        end
    end
    return info
end

function guess_log(run_dir)
    env_dir = dirname(run_dir)
    batch_root = dirname(env_dir)
    candidate = joinpath(batch_root, string(basename(env_dir), ".log"))
    return isfile(candidate) ? candidate : nothing
end

function mtime_dt(path)
    try
        return unix2datetime(round(Int, mtime(path)))
    catch
        return nothing
    end
end

function infer_n_steps(path)
    norm = lowercase(replace(String(path), '\\' => '/', '-' => '_'))
    for seg in split(norm, '/')
        for token in filter(!isempty, split(seg, '_'))
            text = startswith(token, "run") ? token[4:end] : startswith(token, 'n') ? token[2:end] : ""
            isempty(text) && continue
            m = match(r"^(\d+)(k|m)?$", text)
            m === nothing && continue
            base = parse(Int, m.captures[1])
            suffix = m.captures[2]
            return suffix == "m" ? base * 1_000_000 : suffix == "k" ? base * 1_000 : base
        end
    end
    return nothing
end

function discover_runs(root)
    stable = String[]
    skipped = String[]
    now_dt = Dates.now()
    for (dir, _, _) in walkdir(root)
        if isdir(joinpath(dir, "plots"))
            has_manifest = isfile(joinpath(dir, "manifest.tsv"))
            has_alpha = any(name -> occursin(r"^alpha_.*_sched_theory_.*\.csv$", name), readdir(dir))
            if has_manifest || has_alpha
                recent = false
                mod = mtime_dt(dir)
                mod !== nothing && (recent = (now_dt - mod) < Dates.Second(STABILITY_WINDOW_SECONDS))
                done = get(log_info(guess_log(dir)), "done", false)
                (done || !recent ? push!(stable, dir) : push!(skipped, dir))
            end
        end
    end
    sort!(stable)
    sort!(skipped)
    return stable, skipped
end

function ensure_pngs(run_dir)
    plots_dir = joinpath(run_dir, "plots")
    isdir(plots_dir) || return (attempted=false, missing=0, ok=true, msg="no plots")
    missing = 0
    for name in readdir(plots_dir)
        endswith(lowercase(name), ".eps") || continue
        png = replace(name, r"(?i)\.eps$" => ".png")
        isfile(joinpath(plots_dir, png)) || (missing += 1)
    end
    missing == 0 && return (attempted=false, missing=0, ok=true, msg="already complete")
    cmd = `$(Base.julia_cmd()) $(joinpath(@__DIR__, "export_plots_png.jl")) $(run_dir)`
    try
        run(cmd)
        return (attempted=true, missing=missing, ok=true, msg="exported")
    catch err
        return (attempted=true, missing=missing, ok=false, msg=sprint(showerror, err))
    end
end
function key_num(x)
    return isfinite(x) ? @sprintf("%.12e", x) : "na"
end

legacy_key(scale, eigen, kappa) = string(key_num(scale), "|", key_num(eigen), "|", key_num(kappa))
legacy_plot_key(scale, eigen) = string(key_num(scale), "|", key_num(eigen))

function find_ratio_legacy(run_dir, scale, eigen, kappa)
    names = String[]
    if isfinite(kappa)
        push!(names, @sprintf("ratio_scale_%.6e_eigen_%.2e_kappa_%.2e.csv", scale, eigen, kappa))
        push!(names, @sprintf("ratio_omega_%.6e_eigen_%.2e_kappa_%.2e.csv", scale, eigen, kappa))
    end
    push!(names, @sprintf("ratio_scale_%.6e_eigen_%.2e.csv", scale, eigen))
    push!(names, @sprintf("ratio_omega_%.6e_eigen_%.2e.csv", scale, eigen))
    for name in names
        full = joinpath(run_dir, name)
        isfile(full) && return full
    end
    return ""
end

function build_manifest_groups(run_dir)
    groups = Dict{String,Dict{String,Any}}()
    for row in parse_table(joinpath(run_dir, "manifest.tsv"), '\t')
        case_id = get(row, "case_id", "")
        g = get!(groups, case_id) do
            Dict{String,Any}(
                "case_id" => case_id,
                "case_slug" => lowercase(get(row, "case_slug", case_id)),
                "label" => get(row, "case_label", "Case $(case_id)"),
                "env" => get(row, "env_id", "unknown"),
                "meta" => metadata_dict(get(row, "metadata", "")),
                "c" => Float64[],
                "agg" => Dict{Float64,String}(),
                "run" => Dict{Float64,String}(),
                "ratio" => String[],
                "plots" => String[],
                "lambda" => parse_float(get(row, "lambda_min", "")),
                "kappa" => parse_float(get(row, "kappa", "")),
                "gamma" => parse_float(get(row, "gamma", "")),
                "theta_star" => parse_float(get(row, "theta_star_norm", "")),
                "sort" => parse_int(case_id),
            )
        end
        c = parse_float(get(row, "param_value", ""))
        if isfinite(c)
            push!(g["c"], c)
            g["agg"][c] = joinpath(run_dir, get(row, "agg_file", ""))
            g["run"][c] = joinpath(run_dir, get(row, "run_file", ""))
        end
    end
    out = collect(values(groups))
    for g in out
        g["c"] = sort(unique(g["c"]))
        for ext in (".tsv", ".csv")
            ratio = joinpath(run_dir, "ratio_case_$(g["case_id"])$(ext)")
            isfile(ratio) && push!(g["ratio"], ratio)
        end
    end
    sort!(out, by = g -> (g["sort"] === nothing ? typemax(Int) : g["sort"], String(g["case_id"])))
    return out
end

function build_legacy_groups(run_dir)
    groups = Dict{String,Dict{String,Any}}()
    for name in sort(readdir(run_dir))
        full = joinpath(run_dir, name)
        isfile(full) || continue
        meta = parse_alpha(name)
        if !meta.sched || meta.runs || !isfinite(meta.param) || !isfinite(meta.scale) || !isfinite(meta.eigen)
            continue
        end
        key = legacy_key(meta.scale, meta.eigen, meta.kappa)
        g = get!(groups, key) do
            Dict{String,Any}(
                "case_id" => "",
                "case_slug" => @sprintf("scale-%.6e-eigen-%.2e", meta.scale, meta.eigen),
                "label" => @sprintf("ToyExample | scale=%s | eigen=%s | kappa=%s", fmt_short(meta.scale), fmt_short(meta.eigen), fmt_short(meta.kappa)),
                "env" => "toyexample",
                "meta" => Dict{String,String}("scale" => fmt_short(meta.scale), "eigen" => fmt_short(meta.eigen), "kappa" => fmt_short(meta.kappa)),
                "c" => Float64[],
                "agg" => Dict{Float64,String}(),
                "run" => Dict{Float64,String}(),
                "ratio" => String[],
                "plots" => String[],
                "lambda" => NaN,
                "kappa" => meta.kappa,
                "gamma" => NaN,
                "theta_star" => NaN,
                "sort" => (meta.eigen, meta.scale, meta.kappa),
                "plot_key" => legacy_plot_key(meta.scale, meta.eigen),
            )
        end
        push!(g["c"], meta.param)
        g["agg"][meta.param] = full
        run_csv = find_runs_csv(full)
        isfile(run_csv) && (g["run"][meta.param] = run_csv)
    end
    out = collect(values(groups))
    sort!(out, by = g -> g["sort"])
    for (idx, g) in enumerate(out)
        g["case_id"] = @sprintf("legacy-%03d", idx)
        ratio = find_ratio_legacy(run_dir, parse_float(g["meta"]["scale"]), parse_float(g["meta"]["eigen"]), parse_float(g["meta"]["kappa"]))
        !isempty(ratio) && push!(g["ratio"], ratio)
        for agg_path in values(g["agg"])
            row = csv_last_row(agg_path)
            g["lambda"] = parse_float(get(row, "lambda_min", string(g["lambda"])))
            g["gamma"] = parse_float(get(row, "gamma", string(g["gamma"])))
            g["theta_star"] = parse_float(get(row, "||theta^*||^2", string(g["theta_star"])))
            break
        end
        g["c"] = sort(unique(g["c"]))
    end
    return out
end

function plot_assets(run_dir)
    assets = Dict{String,Dict{String,String}}()
    plots_dir = joinpath(run_dir, "plots")
    isdir(plots_dir) || return assets
    for name in sort(readdir(plots_dir))
        ext = lowercase(splitext(name)[2])
        ext in (".png", ".eps") || continue
        base = splitext(name)[1]
        entry = get!(assets, base) do
            Dict{String,String}("png" => "", "eps" => "")
        end
        entry[ext == ".png" ? "png" : "eps"] = joinpath(plots_dir, name)
    end
    return assets
end

function classify_plot(base)
    low = lowercase(base)
    if occursin("__finalgrid__", low)
        return (type="finalgrid", obj="grid", label="Global final grid", is_global=true)
    elseif occursin("__compact__", low)
        return (type="compact", obj="compact", label="Compact grid", is_global=true)
    elseif occursin("learning_curves_grid_d", low)
        return (type="learning-grid-d", obj="D", label="Learning curves grid (D)", is_global=true)
    elseif occursin("learning_curves_grid_a", low)
        return (type="learning-grid-a", obj="A", label="Learning curves grid (A)", is_global=true)
    elseif occursin("__bestcurves__", low)
        return (type="best", obj="best", label="Best learning curves", is_global=true)
    elseif occursin("__final__", low)
        return (type="final", obj="final", label="Final analysis", is_global=false)
    elseif occursin("__curves__", low) && occursin("d+gammas", low)
        return (type="curve-a", obj="A", label="Learning curve (A objective)", is_global=false)
    elseif occursin("__curves__", low)
        return (type="curve-d", obj="D", label="Learning curve (D objective)", is_global=false)
    else
        return (type="other", obj="other", label="Unclassified plot", is_global=false)
    end
end

function legacy_plot_match(base)
    m = match(r"eig-([0-9eE+\-.]+)__scale-([0-9eE+\-.]+)", base)
    m === nothing && return nothing
    return legacy_plot_key(parse(Float64, m.captures[2]), parse(Float64, m.captures[1]))
end

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
        card["case_label"] = String(group["label"])
        card["search"] = lowercase(String(group["label"]) * " " * base)
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

function divergence_rows(groups)
    acc = Dict{Float64,Tuple{Int,Int}}()
    for g in groups
        for c in g["c"]
            path = get(g["run"], c, "")
            isfile(path) || continue
            st = run_stats(path)
            total, divs = get(acc, c, (0, 0))
            acc[c] = (total + st.n, divs + st.d)
        end
    end
    rows = Dict{String,Any}[]
    for c in sort(collect(keys(acc)))
        total, divs = acc[c]
        push!(rows, Dict{String,Any}("c" => c, "total" => total, "diverged" => divs, "rate" => total == 0 ? 0.0 : divs / total))
    end
    return rows
end

function metric_rows(groups)
    vals = Dict(
        "last timestep" => Float64[],
        "final D objective" => Float64[],
        "final A objective" => Float64[],
        "final theta norm" => Float64[],
        "max theta norm" => Float64[],
    )
    for g in groups
        for agg_path in values(g["agg"])
            row = csv_last_row(agg_path)
            isempty(row) && continue
            push!(vals["last timestep"], parse_float(get(row, "timestep", "")))
            push!(vals["final D objective"], parse_float(get(row, "E_D[||Vbar_t - V*||^2]", "")))
            push!(vals["final A objective"], parse_float(get(row, "E_A[||Vbar_t - V*||^2]", "")))
            push!(vals["final theta norm"], parse_float(get(row, "E[||theta_t||^2]", "")))
            push!(vals["max theta norm"], parse_float(get(row, "max_i<=T ||theta_i||^2", "")))
        end
    end
    out = Dict{String,Any}[]
    for label in keys(vals)
        usable = sort(filter(isfinite, vals[label]))
        if isempty(usable)
            push!(out, Dict("label" => label, "min" => NaN, "median" => NaN, "max" => NaN))
        else
            push!(out, Dict("label" => label, "min" => first(usable), "median" => median(usable), "max" => last(usable)))
        end
    end
    return out
end
function badges(meta)
    isempty(meta) && return "<span class='muted'>none</span>"
    return join(["<span class='badge badge-plain'><code>$(esc_html(k))=$(esc_html(meta[k]))</code></span>" for k in sort(collect(keys(meta)))], " ")
end

function file_links(paths, base_dir)
    isempty(paths) && return "<span class='muted'>none</span>"
    items = ["<li><a href='$(url_path(relpath(path, base_dir)))'><code>$(esc_html(relpath(path, base_dir)))</code></a></li>" for path in sort(unique(paths))]
    return "<details><summary>$(length(items)) files</summary><ul class='file-list'>$(join(items, ""))</ul></details>"
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
    return "<article class='plot-card' data-gallery-card='1' data-search='$(esc_html(card["search"]))' data-plot-type='$(esc_html(card["type"]))' data-case-id='$(esc_html(card["case_id"]))' data-objective='$(esc_html(card["obj"]))' data-c-values='$(esc_html(cset))'><div class='plot-head'><h3>$(esc_html(card["case_label"]))</h3><div class='plot-file'><code>$(esc_html(card["base"]))</code></div></div><div class='badge-row'>$(join(info, " "))</div>$(warn)$(img)<div class='plot-links'>$(isempty(links) ? "<span class='muted'>no file links</span>" : join(links, " · "))</div></article>"
end

function global_card(card, run_dir)
    img = !isempty(card["src"]) ? "<img loading='lazy' src='$(url_path(relpath(card["src"], run_dir)))' alt='$(esc_html(card["base"]))'>" : "<div class='image-warning'>PNG unavailable for inline display.</div>"
    links = String[]
    !isempty(card["png"]) && push!(links, "<a href='$(url_path(relpath(card["png"], run_dir)))'>PNG</a>")
    !isempty(card["eps"]) && push!(links, "<a href='$(url_path(relpath(card["eps"], run_dir)))'>EPS</a>")
    return "<article class='global-card'><div class='plot-head'><h3>$(esc_html(card["label"]))</h3><div class='plot-file'><code>$(esc_html(card["base"]))</code></div></div>$(img)<div class='plot-links'>$(isempty(links) ? "<span class='muted'>no file links</span>" : join(links, " · "))</div></article>"
end

function parameter_table(groups, run_dir)
    rows = String[]
    for g in groups
        agg = [g["agg"][c] for c in sort(collect(keys(g["agg"]))) if isfile(g["agg"][c])]
        run = [g["run"][c] for c in sort(collect(keys(g["run"]))) if isfile(g["run"][c])]
        ratio = filter(isfile, String[g["ratio"]...])
        push!(rows, "<tr><td><code>$(esc_html(g["case_id"]))</code></td><td>$(esc_html(g["env"]))</td><td>$(esc_html(g["label"]))</td><td><code>$(esc_html(join(fmt_short.(g["c"]), ", ")))</code></td><td><code>$(esc_html(fmt_num(g["lambda"])))</code></td><td><code>$(esc_html(fmt_num(g["kappa"])))</code></td><td><code>$(esc_html(fmt_num(g["gamma"])))</code></td><td><code>$(esc_html(fmt_num(g["theta_star"])))</code></td><td>$(badges(g["meta"]))</td><td>$(file_links(agg, run_dir))</td><td>$(file_links(run, run_dir))</td><td>$(file_links(ratio, run_dir))</td></tr>")
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
        push!(rows, "<tr><td><code>$(esc_html(g["case_id"]))</code></td><td>$(esc_html(g["label"]))</td><td>$(file_links(agg, run_dir))</td><td>$(file_links(run, run_dir))</td><td>$(file_links(ratio, run_dir))</td><td>$(file_links(plots, run_dir))</td></tr>")
    end
    return join(rows, "")
end

function family_rows(cards)
    counts = Dict{String,Int}()
    for card in cards
        counts[card["type"]] = get(counts, card["type"], 0) + 1
    end
    rows = String[]
    for key in sort(collect(keys(counts)))
        push!(rows, "<tr><td><code>$(esc_html(key))</code></td><td>$(counts[key])</td></tr>")
    end
    return isempty(rows) ? "<tr><td colspan='2' class='muted'>No plots found.</td></tr>" : join(rows, "")
end

const REPORT_STYLE = "<style>:root{--bg:#f5f0e8;--ink:#1b1b18;--muted:#5e5a53;--card:#fffdf8;--line:#d9cbb8;--accent:#8e3b1b;--chip:#f8f2ea;--shadow:0 14px 40px rgba(62,43,30,.10);}*{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;font-family:'Iowan Old Style','Palatino Linotype','Book Antiqua','Noto Serif TC',serif;background:radial-gradient(circle at top,#fffaf2 0%,#f5f0e8 48%,#efe7db 100%);color:var(--ink);line-height:1.55}a{color:var(--accent)}code{font-family:'Cascadia Mono','Consolas','SFMono-Regular',monospace;background:#f6eee4;border:1px solid #ead9c7;border-radius:6px;padding:.08rem .35rem}.page{max-width:1600px;margin:0 auto;padding:32px 24px 80px}.hero{padding:28px;border:1px solid var(--line);border-radius:26px;background:linear-gradient(135deg,#fffdf9 0%,#f8efe5 100%);box-shadow:var(--shadow)}.hero-top{display:flex;justify-content:space-between;gap:18px;align-items:flex-start;flex-wrap:wrap}.hero h1{margin:.1rem 0 .25rem;font-size:clamp(2rem,3vw,3.2rem);line-height:1.05}.subtle,.muted{color:var(--muted)}.pill{display:inline-flex;align-items:center;gap:.4rem;padding:.38rem .7rem;border-radius:999px;background:var(--chip);border:1px solid var(--line);margin:.15rem .3rem .15rem 0;font-size:.92rem}.hero-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:12px;margin-top:18px}.hero-stat{padding:14px;border-radius:18px;background:rgba(255,255,255,.8);border:1px solid var(--line)}.hero-stat .label{display:block;font-size:.84rem;color:var(--muted)}.hero-stat .value{display:block;font-size:1.18rem;font-weight:700;margin-top:6px}.section{margin-top:28px}.section h2{margin:0 0 14px;font-size:1.45rem}.table-wrap{overflow:auto;border:1px solid var(--line);border-radius:18px;background:var(--card);box-shadow:var(--shadow)}table{width:100%;border-collapse:collapse;font-size:.95rem}th,td{padding:12px 14px;border-bottom:1px solid #eadfce;vertical-align:top}th{text-align:left;background:#f8f2ea}tr:last-child td{border-bottom:none}.grid-2{display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:18px}.global-card,.plot-card,.note-card{background:var(--card);border:1px solid var(--line);border-radius:22px;padding:18px;box-shadow:var(--shadow)}.global-card img,.plot-card img{width:100%;height:auto;border-radius:16px;border:1px solid #e4d6c7;background:#fff}.plot-head{display:flex;justify-content:space-between;gap:12px;align-items:baseline;flex-wrap:wrap;margin-bottom:10px}.plot-head h3{margin:0;font-size:1.05rem}.plot-file{color:var(--muted);font-size:.82rem}.badge-row{display:flex;flex-wrap:wrap;gap:8px;margin:0 0 12px}.badge{display:inline-flex;align-items:center;padding:.26rem .55rem;border-radius:999px;background:var(--chip);border:1px solid var(--line);font-size:.8rem}.badge-plain{display:inline-flex;align-items:center;margin:.15rem .25rem .15rem 0}.callout{padding:12px 14px;border-radius:16px;border:1px solid var(--line);background:#fff9f3;margin-bottom:12px}.callout.warn{border-color:#d78f68;background:#fff2ea}.filters{position:sticky;top:10px;z-index:10;padding:16px;border:1px solid var(--line);border-radius:20px;background:rgba(255,251,245,.94);backdrop-filter:blur(10px);box-shadow:var(--shadow)}.filter-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:12px}.filter-grid label{display:flex;flex-direction:column;gap:6px;font-size:.88rem;color:var(--muted)}input,select{width:100%;padding:10px 12px;border-radius:12px;border:1px solid #d8c8b6;background:white;font:inherit;color:var(--ink)}.gallery{display:grid;grid-template-columns:repeat(auto-fit,minmax(360px,1fr));gap:18px}.image-warning{min-height:220px;display:grid;place-items:center;border-radius:16px;border:1px dashed #c9ae98;background:#fbf6ef;color:var(--muted);padding:18px;text-align:center}.plot-links{margin-top:10px;font-size:.9rem}.file-list{margin:.7rem 0 0;padding-left:1.2rem}.top-links{display:flex;flex-wrap:wrap;gap:10px}.tiny{font-size:.84rem}.unmatched{margin-top:22px}.summary-cards{display:grid;grid-template-columns:repeat(auto-fit,minmax(220px,1fr));gap:14px}.summary-cards .note-card{min-height:100%}@media (max-width:720px){.page{padding:22px 14px 60px}.hero{padding:20px}.gallery{grid-template-columns:1fr}}</style>"

const INDEX_STYLE = "<style>:root{--bg:#f6f1e8;--ink:#201d19;--muted:#5f594f;--card:#fffdf9;--line:#dccdb8;--accent:#8b3f1f;--shadow:0 18px 40px rgba(61,46,33,.10);}*{box-sizing:border-box}body{margin:0;font-family:'Iowan Old Style','Palatino Linotype','Book Antiqua','Noto Serif TC',serif;background:linear-gradient(180deg,#fffaf2 0%,#f6f1e8 42%,#efe7dc 100%);color:var(--ink)}a{color:var(--accent)}code{font-family:'Cascadia Mono','Consolas',monospace;background:#f6eee4;border:1px solid #ead9c7;border-radius:6px;padding:.08rem .35rem}.page{max-width:1500px;margin:0 auto;padding:32px 24px 80px}.hero{padding:28px;border-radius:26px;border:1px solid var(--line);background:linear-gradient(135deg,#fffdf9 0%,#f9efe5 100%);box-shadow:var(--shadow)}.hero h1{margin:0 0 .35rem;font-size:clamp(2.2rem,3.5vw,3.6rem)}.hero p{margin:0;color:var(--muted)}.hero-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:12px;margin-top:18px}.stat{padding:14px;border-radius:18px;border:1px solid var(--line);background:rgba(255,255,255,.82)}.stat .label{display:block;font-size:.84rem;color:var(--muted)}.stat .value{display:block;font-size:1.24rem;font-weight:700;margin-top:6px}.controls{position:sticky;top:12px;z-index:10;margin-top:24px;padding:16px;border-radius:20px;border:1px solid var(--line);background:rgba(255,251,245,.94);backdrop-filter:blur(10px);box-shadow:var(--shadow)}.control-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:12px}.control-grid label{display:flex;flex-direction:column;gap:6px;font-size:.88rem;color:var(--muted)}input,select{width:100%;padding:10px 12px;border-radius:12px;border:1px solid #d8c8b6;background:#fff;font:inherit;color:var(--ink)}.run-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:18px;margin-top:20px}.run-card{padding:18px;border-radius:22px;border:1px solid var(--line);background:var(--card);box-shadow:var(--shadow)}.run-card h2{margin:0 0 .2rem;font-size:1.18rem}.run-card .path{font-size:.86rem;color:var(--muted)}.meta{display:flex;flex-wrap:wrap;gap:8px;margin:12px 0}.badge{display:inline-flex;align-items:center;padding:.28rem .58rem;border-radius:999px;background:#f8f2ea;border:1px solid var(--line);font-size:.8rem}.run-metrics{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px;margin-top:12px}.run-metrics .cell{padding:10px;border-radius:16px;background:#fcf7ef;border:1px solid #eadccc}.run-metrics .k{display:block;color:var(--muted);font-size:.78rem}.run-metrics .v{display:block;margin-top:5px;font-size:1rem;font-weight:700}.section{margin-top:30px}.note{padding:14px 16px;border-radius:18px;border:1px solid var(--line);background:#fff8f0;color:var(--muted)}.muted{color:var(--muted)}@media (max-width:720px){.page{padding:22px 14px 60px}.hero{padding:20px}}</style>"
function build_run_report(run_dir, root)
    format = isfile(joinpath(run_dir, "manifest.tsv")) ? :manifest : :legacy
    warn = String[]
    png = ensure_pngs(run_dir)
    png.attempted && push!(warn, png.ok ? "PNG export completed for missing images." : "PNG export incomplete: $(png.msg)")
    groups = format == :manifest ? build_manifest_groups(run_dir) : build_legacy_groups(run_dir)
    assets = plot_assets(run_dir)
    globals, gallery, unmatched = attach_plots(groups, assets, format)
    isempty(assets) && push!(warn, "No plot images were found under plots/. This usually means upstream plotting failed for this run; CSV files and parameters are still indexed here.")
    !isempty(unmatched) && push!(warn, "$(length(unmatched)) plot(s) could not be matched to a case and are listed separately.")
    envs = sort(unique([String(g["env"]) for g in groups]))
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
    threads = get(log_info(guess_log(run_dir)), "threads", nothing)
    last_mod = mtime_dt(run_dir)
    generated = Dates.now()
    csv_count = count(name -> endswith(lowercase(name), ".csv"), readdir(run_dir))
    tsv_count = count(name -> endswith(lowercase(name), ".tsv"), readdir(run_dir))
    eps_count = count(a -> !isempty(a["eps"]), values(assets))
    png_count = count(a -> !isempty(a["png"]), values(assets))
    missing_png = count(a -> !isempty(a["eps"]) && isempty(a["png"]), values(assets))
    plot_count = length(assets)
    png_complete = plot_count > 0 && missing_png == 0
    div_rows = divergence_rows(groups)
    met_rows = metric_rows(groups)
    params = [
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
    case_ids = sort(unique([c["case_id"] for c in gallery]))
    plot_types = sort(unique([c["type"] for c in gallery]))
    objectives = sort(unique([c["obj"] for c in gallery]))
    open(report_path, "w") do io
        print(io, "<!doctype html><html lang='zh-Hant'><head><meta charset='utf-8'><meta name='viewport' content='width=device-width, initial-scale=1'><title>", esc_html(basename(run_dir)), " | TD Runs Report</title>", REPORT_STYLE, "</head><body><div class='page'>")
        print(io, "<section class='hero'><div class='hero-top'><div><div class='top-links'><a class='pill' href='", url_path(relpath(joinpath(root, "index.html"), run_dir)), "'>Back to index</a><span class='pill'><code>", esc_html(relpath(run_dir, root)), "</code></span></div><h1>", esc_html(basename(run_dir)), "</h1><p class='subtle'>Static experiment viewer for local file browsing. Images are embedded directly in this page when PNGs are available.</p></div><div>")
        for env in first(envs, min(length(envs), MAX_ENV_BADGES))
            print(io, "<span class='pill'>env: <strong>", esc_html(env), "</strong></span>")
        end
        print(io, "</div></div><div class='hero-grid'><div class='hero-stat'><span class='label'>Cases</span><span class='value'>", length(groups), "</span></div><div class='hero-stat'><span class='label'>c values</span><span class='value'>", length(c_grid), "</span></div><div class='hero-stat'><span class='label'>Plot assets</span><span class='value'>", plot_count, "</span></div><div class='hero-stat'><span class='label'>PNG completeness</span><span class='value'>", plot_count == 0 ? "no plots" : png_complete ? "complete" : "$(png_count)/$(plot_count)", "</span></div><div class='hero-stat'><span class='label'>Generated at</span><span class='value tiny'>", esc_html(fmt_dt(generated)), "</span></div><div class='hero-stat'><span class='label'>Run modified</span><span class='value tiny'>", esc_html(fmt_dt(last_mod)), "</span></div></div>")
        for msg in warn
            print(io, "<div class='callout warn'>", esc_html(msg), "</div>")
        end
        print(io, "</section>")
        print(io, "<section class='section'><h2>Batch Parameters</h2><div class='table-wrap'><table><thead><tr><th>Parameter</th><th>Value</th><th>Source</th></tr></thead><tbody>")
        for (label, value, source) in params
            print(io, "<tr><td>", esc_html(label), "</td><td><code>", esc_html(value), "</code></td><td>", esc_html(source), "</td></tr>")
        end
        print(io, "</tbody></table></div></section>")
        print(io, "<section class='section'><h2>Result Summary</h2><div class='summary-cards'><article class='note-card'><h3>Divergence by c</h3><div class='table-wrap'><table><thead><tr><th>c</th><th>total runs</th><th>diverged</th><th>rate</th></tr></thead><tbody>")
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
        "case_count" => length(groups),
        "c_count" => length(c_grid),
        "n_runs" => n_runs,
        "n_steps" => n_steps,
        "threads" => threads,
        "plot_count" => plot_count,
        "png_complete" => png_complete,
        "manifest" => isfile(joinpath(run_dir, "manifest.tsv")),
        "log" => guess_log(run_dir) !== nothing,
        "last_modified" => last_mod,
        "report_path" => report_path,
    )
end

function render_index(root, summaries, skipped)
    env_lists = [Vector{String}(s["envs"]) for s in summaries if !isempty(s["envs"])]
    envs = isempty(env_lists) ? String[] : sort(unique(vcat(env_lists...)))
    open(joinpath(root, "index.html"), "w") do io
        print(io, "<!doctype html><html lang='zh-Hant'><head><meta charset='utf-8'><meta name='viewport' content='width=device-width, initial-scale=1'><title>TD Runs Viewer</title>", INDEX_STYLE, "</head><body><div class='page'><section class='hero'><h1>TD Runs Viewer</h1><p>Static HTML index for local experiment browsing. Each run links to a full report with inline plots and detailed parameters.</p><div class='hero-grid'><div class='stat'><span class='label'>Stable runs indexed</span><span class='value'>", length(summaries), "</span></div><div class='stat'><span class='label'>Distinct envs</span><span class='value'>", length(envs), "</span></div><div class='stat'><span class='label'>PNG complete runs</span><span class='value'>", count(s -> s["png_complete"], summaries), "</span></div><div class='stat'><span class='label'>Skipped active runs</span><span class='value'>", length(skipped), "</span></div></div></section><section class='controls'><div class='control-grid'><label>Search<input id='run-search' type='search' placeholder='run label, env, path'></label><label>Env<select id='run-env'><option value='all'>show all</option>")
        for env in envs
            print(io, "<option value='", esc_html(env), "'>", esc_html(env), "</option>")
        end
        print(io, "</select></label><label>Sort<select id='run-sort'><option value='date-desc'>newest first</option><option value='date-asc'>oldest first</option><option value='name-asc'>name A→Z</option><option value='env-asc'>env A→Z</option><option value='png-desc'>PNG complete first</option></select></label></div><p class='muted'>Visible runs: <span id='run-count'>0</span></p></section><section class='section'><div id='run-grid' class='run-grid'>")
        for s in summaries
            report_rel = url_path(relpath(s["report_path"], root))
            search = lowercase(s["run_label"] * " " * s["rel_dir"] * " " * join(s["envs"], " "))
            env_join = join(s["envs"], "|")
            date_val = s["last_modified"] === nothing ? 0 : Dates.value(s["last_modified"])
            print(io, "<article class='run-card' data-search='", esc_html(search), "' data-envs='", esc_html(env_join), "' data-date='", date_val, "' data-name='", esc_html(lowercase(s["run_label"])), "' data-png='", s["png_complete"] ? 1 : 0, "'><div class='path'><code>", esc_html(s["rel_dir"]), "</code></div><h2>", esc_html(s["run_label"]), "</h2><div class='meta'>")
            for env in s["envs"]
                print(io, "<span class='badge'>env: ", esc_html(env), "</span>")
            end
            print(io, "<span class='badge'>", s["plot_count"] == 0 ? "no plots" : s["png_complete"] ? "PNG complete" : "PNG partial", "</span>", s["manifest"] ? "<span class='badge'>manifest</span>" : "<span class='badge'>legacy</span>", s["log"] ? "<span class='badge'>log</span>" : "<span class='badge'>no log</span>", "</div><div class='run-metrics'><div class='cell'><span class='k'>cases</span><span class='v'>", s["case_count"], "</span></div><div class='cell'><span class='k'>c count</span><span class='v'>", s["c_count"], "</span></div><div class='cell'><span class='k'>n_runs</span><span class='v'>", s["n_runs"] === nothing ? "not recorded" : string(s["n_runs"]), "</span></div><div class='cell'><span class='k'>n_steps</span><span class='v'>", s["n_steps"] === nothing ? "not recorded" : string(s["n_steps"]), "</span></div><div class='cell'><span class='k'>threads</span><span class='v'>", s["threads"] === nothing ? "not recorded" : string(s["threads"]), "</span></div><div class='cell'><span class='k'>plots</span><span class='v'>", s["plot_count"], "</span></div></div><p class='muted'>modified: ", esc_html(fmt_dt(s["last_modified"])), "</p><p><a href='", report_rel, "'>Open report</a></p></article>")
        end
        print(io, "</div></section>")
        if !isempty(skipped)
            print(io, "<section class='section'><h2>Skipped Active Runs</h2><div class='note'><p>The following run directories were skipped because they changed within the last ", STABILITY_WINDOW_SECONDS, " seconds or their environment log has not finished yet. Re-run the generator after the batch completes.</p><ul>")
            for dir in skipped
                print(io, "<li><code>", esc_html(relpath(dir, root)), "</code></li>")
            end
            print(io, "</ul></div></section>")
        end
        print(io, "<script>const cards=[...document.querySelectorAll('.run-card')];const grid=document.getElementById('run-grid');function applyRunFilters(){const q=(document.getElementById('run-search').value||'').toLowerCase();const env=document.getElementById('run-env').value;const sort=document.getElementById('run-sort').value;const visible=[];for(const card of cards){const search=(card.dataset.search||'').toLowerCase();const envs=(card.dataset.envs||'').split('|').filter(Boolean);const show=(!q||search.includes(q))&&(env==='all'||envs.includes(env));card.hidden=!show;if(show)visible.push(card);}visible.sort((a,b)=>{if(sort==='date-asc')return Number(a.dataset.date)-Number(b.dataset.date);if(sort==='name-asc')return a.dataset.name.localeCompare(b.dataset.name);if(sort==='env-asc')return a.dataset.envs.localeCompare(b.dataset.envs)||a.dataset.name.localeCompare(b.dataset.name);if(sort==='png-desc')return Number(b.dataset.png)-Number(a.dataset.png)||Number(b.dataset.date)-Number(a.dataset.date);return Number(b.dataset.date)-Number(a.dataset.date);});for(const card of visible){grid.appendChild(card);}document.getElementById('run-count').textContent=(visible.length + ' / ' + cards.length);}['run-search','run-env','run-sort'].forEach(id=>document.getElementById(id).addEventListener('input',applyRunFilters));applyRunFilters();</script></div></body></html>")
    end
end

function main(args)
    root = parse_args(args)
    isdir(root) || error("Root directory not found: $(root)")
    stable, skipped = discover_runs(root)
    summaries = Dict{String,Any}[]
    for run_dir in stable
        println("[report] ", relpath(run_dir, root))
        push!(summaries, build_run_report(run_dir, root))
    end
    sort!(summaries, by = s -> s["last_modified"] === nothing ? DateTime(1900,1,1) : s["last_modified"], rev=true)
    render_index(root, summaries, skipped)
    println("[done] index => ", joinpath(root, "index.html"))
end

include(joinpath(@__DIR__, "td_instance_report_overrides.jl"))

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end






