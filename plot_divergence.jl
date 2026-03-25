#!/usr/bin/env julia

using Printf
using LaTeXStrings

ENV["MPLBACKEND"] = get(ENV, "MPLBACKEND", "Agg")
const HAVE_PYPLOT = let ok = true
    try
        @eval import PyPlot
    catch
        ok = false
    end
    ok
end

if HAVE_PYPLOT
    const plt_global = PyPlot
    use_tex = get(ENV, "PLOT_USE_TEX", "0") == "1"
    try
        plt_global.rc("text", usetex=use_tex)
        if use_tex
            plt_global.rc("font", family="serif")
        end
    catch
        plt_global.rc("text", usetex=false)
    end
end

const Y_MIN_OBJ = 1e-6
const Y_MAX_OBJ = 1e12
const Y_MIN_RATIO = 1e-6
const Y_MAX_RATIO = 1e12
const CURVE_MIN_OBJ = 1e-6
const CURVE_MAX_OBJ = 1e12
const PLOT_CAP_VALUE = 1e24

function _safe_savefig(plt, path::AbstractString)
    try
        Base.invokelatest(plt.savefig, path)
    catch e
        try
            plt.rc("text", usetex=false)
            Base.invokelatest(plt.savefig, path)
        catch
            rethrow(e)
        end
    end
end

sanitize_val(v::Float64) = !isfinite(v) ? PLOT_CAP_VALUE : min(v, PLOT_CAP_VALUE)

function clamp_vec(y::AbstractVector, ymin::Float64, ymax::Float64)
    out = similar(y, Float64)
    @inbounds for i in eachindex(y)
        v = sanitize_val(float(y[i]))
        if v <= 0 && ymin > 0
            v = ymin
        end
        out[i] = min(max(v, ymin), ymax)
    end
    return out
end

function valid_xy(x::AbstractVector{<:Real}, y::AbstractVector{<:Real})
    xx = Float64[]
    yy = Float64[]
    n = min(length(x), length(y))
    @inbounds for i in 1:n
        xi = float(x[i])
        yi = sanitize_val(float(y[i]))
        if isfinite(xi) && isfinite(yi) && xi > 0 && yi > 0
            push!(xx, xi)
            push!(yy, yi)
        end
    end
    return xx, yy
end

function short_label(s::AbstractString; maxlen::Int=64)
    text = replace(String(s), '\t' => ' ')
    if lastindex(text) <= maxlen
        return text
    end
    return string(first(text, maxlen - 3), "...")
end

function slugify(s::AbstractString)
    text = lowercase(strip(String(s)))
    text = replace(text, ' ' => '-', '|' => '-', '=' => '-', ',' => '-', ';' => '-', '/' => '-', '\\' => '-')
    text = replace(text, "--" => "-")
    return strip(text, '-')
end

function parse_alpha_filename(path::AbstractString)
    base = splitext(basename(path))[1]
    parts = split(base, "_")
    if length(parts) < 2 || parts[1] != "alpha"
        return (param=NaN, scale=NaN, eigen=NaN, kappa=NaN, case_id="", is_sched=false, has_runs=false)
    end
    param = try parse(Float64, parts[2]) catch; NaN end
    scale = NaN
    eigen = NaN
    kappa = NaN
    case_id = ""
    is_sched = false
    has_runs = false
    i = 3
    while i <= length(parts)
        token = parts[i]
        if token == "runs"
            has_runs = true
            i += 1
        elseif token == "sched" && i + 1 <= length(parts) && parts[i + 1] == "theory"
            is_sched = true
            i += 2
        elseif token == "scale" && i + 1 <= length(parts)
            scale = try parse(Float64, parts[i + 1]) catch; NaN end
            i += 2
        elseif token == "omega" && i + 1 <= length(parts)
            scale = try parse(Float64, parts[i + 1]) catch; NaN end
            i += 2
        elseif token == "eigen" && i + 1 <= length(parts)
            eigen = try parse(Float64, parts[i + 1]) catch; NaN end
            i += 2
        elseif token == "kappa" && i + 1 <= length(parts)
            kappa = try parse(Float64, parts[i + 1]) catch; NaN end
            i += 2
        elseif token == "case" && i + 1 <= length(parts)
            case_id = parts[i + 1]
            i += 2
        else
            i += 1
        end
    end
    return (param=param, scale=scale, eigen=eigen, kappa=kappa, case_id=case_id, is_sched=is_sched, has_runs=has_runs)
end

function find_runs_csv(path::AbstractString)
    meta = parse_alpha_filename(path)
    base_dir = dirname(path)
    candidates = String[]
    if !isempty(meta.case_id)
        push!(candidates, @sprintf("alpha_%.2e_runs_sched_theory_case_%s.csv", meta.param, meta.case_id))
    end
    if meta.is_sched
        if isfinite(meta.kappa)
            push!(candidates, @sprintf("alpha_%.2e_runs_sched_theory_scale_%.6e_eigen_%.2e_kappa_%.2e.csv", meta.param, meta.scale, meta.eigen, meta.kappa))
            push!(candidates, @sprintf("alpha_%.2e_runs_sched_theory_omega_%.6e_eigen_%.2e_kappa_%.2e.csv", meta.param, meta.scale, meta.eigen, meta.kappa))
        end
        push!(candidates, @sprintf("alpha_%.2e_runs_sched_theory_scale_%.6e_eigen_%.2e.csv", meta.param, meta.scale, meta.eigen))
        push!(candidates, @sprintf("alpha_%.2e_runs_sched_theory_omega_%.6e_eigen_%.2e.csv", meta.param, meta.scale, meta.eigen))
    else
        push!(candidates, @sprintf("alpha_%.2e_runs_scale_%.6e_eigen_%.2e.csv", meta.param, meta.scale, meta.eigen))
    end
    for name in candidates
        full = joinpath(base_dir, name)
        if isfile(full)
            return full
        end
    end
    return isempty(candidates) ? "" : joinpath(base_dir, first(candidates))
end

function print_help()
    scr = basename(@__FILE__)
    println("""
Usage: julia $scr --dir <output_dir>

Options:
  --dir <Str>       results directory to plot
  -h, --help        show this help and exit
""")
end

function parse_args(args)
    dir = nothing
    i = 1
    while i <= length(args)
        arg = args[i]
        if arg == "--help" || arg == "-h"
            print_help()
            exit(0)
        elseif arg == "--dir" && i < length(args)
            dir = args[i + 1]
            i += 2
            continue
        else
            @printf("Unknown or incomplete arg: %s\n", arg)
            i += 1
        end
    end
    dir === nothing && error("Usage: julia plot_divergence.jl --dir <output_dir>")
    return (dir=dir,)
end

function read_aggregated_csv(path::AbstractString)
    open(path, "r") do io
        _ = readline(io)
        first_line = nothing
        last_line = nothing
        for line in eachline(io)
            first_line === nothing && (first_line = line)
            last_line = line
        end
        last_line === nothing && error("Empty CSV: $path")
        function parse_row(line)
            parts = split(chomp(line), ",")
            return (
                t=parse(Int, parts[1]),
                avg_vbar=parse(Float64, parts[2]),
                avg_vbar_A=parse(Float64, parts[3]),
                avg_theta_norm=parse(Float64, parts[4]),
                max_avg_theta=parse(Float64, parts[5]),
                theta_star_norm=parse(Float64, parts[6]),
                std_vbar=length(parts) >= 7 ? parse(Float64, parts[7]) : NaN,
                std_vbar_A=length(parts) >= 8 ? parse(Float64, parts[8]) : NaN,
                max_std_theta=length(parts) >= 9 ? parse(Float64, parts[9]) : NaN,
                lambda_min=length(parts) >= 10 ? parse(Float64, parts[10]) : NaN,
                kappa=length(parts) >= 11 ? parse(Float64, parts[11]) : NaN,
                gamma=length(parts) >= 12 ? parse(Float64, parts[12]) : NaN,
            )
        end
        return parse_row(first_line), parse_row(last_line)
    end
end

function read_run_csv(path::AbstractString)
    open(path, "r") do io
        _ = readline(io)
        n = 0
        div = 0
        for line in eachline(io)
            parts = split(chomp(line), ",")
            n += 1
            if length(parts) >= 2
                div += parse(Int, parts[2])
            end
        end
        return (n_runs=n, divergence_rate=n == 0 ? 0.0 : div / n)
    end
end

function read_manifest(outdir::AbstractString)
    path = joinpath(outdir, "manifest.tsv")
    isfile(path) || return nothing
    rows = NamedTuple[]
    open(path, "r") do io
        header = split(chomp(readline(io)), '\t')
        for line in eachline(io)
            parts = split(chomp(line), '\t')
            length(parts) == length(header) || continue
            row = NamedTuple{Tuple(Symbol.(header))}(Tuple(parts))
            push!(rows, row)
        end
    end
    return rows
end

function collect_groups_from_manifest(outdir::AbstractString, manifest_rows)
    by_case = Dict{String, Vector{NamedTuple}}()
    for row in manifest_rows
        push!(get!(by_case, row.case_id, NamedTuple[]), row)
    end
    groups = NamedTuple[]
    for case_id in sort(collect(keys(by_case)))
        rows = sort(by_case[case_id], by = r -> parse(Float64, r.param_value))
        push!(groups, (
            group_id=case_id,
            label=rows[1].case_label,
            slug=string("case-", case_id),
            param_name=rows[1].param_name,
            entries=[(
                param=parse(Float64, row.param_value),
                agg_path=joinpath(outdir, row.agg_file),
                run_path=joinpath(outdir, row.run_file),
                lambda_min=parse(Float64, row.lambda_min),
                kappa=parse(Float64, row.kappa),
                gamma=parse(Float64, row.gamma),
            ) for row in rows],
        ))
    end
    env_name = isempty(groups) ? split(basename(outdir), "_")[1] : manifest_rows[1].env_id
    return env_name, groups
end

function collect_groups_legacy(outdir::AbstractString)
    files = filter(f -> occursin("alpha_", basename(f)) && endswith(f, ".csv") && !occursin("_runs_", basename(f)), readdir(outdir; join=true))
    isempty(files) && error("No aggregated alpha_*.csv files found in $outdir")
    grouped = Dict{String, Vector{String}}()
    labels = Dict{String, String}()
    param_names = Dict{String, String}()
    slugs = Dict{String, String}()
    for f in files
        meta = parse_alpha_filename(f)
        gid = if !isempty(meta.case_id)
            string("case-", meta.case_id)
        elseif isfinite(meta.scale)
            @sprintf("scale-%.3e", meta.scale)
        elseif isfinite(meta.eigen)
            @sprintf("lambda-%.3e", meta.eigen)
        else
            slugify(basename(f))
        end
        push!(get!(grouped, gid, String[]), f)
        if !haskey(labels, gid)
            labels[gid] = if isfinite(meta.scale)
                @sprintf("scale=%.3e", meta.scale)
            elseif isfinite(meta.eigen)
                @sprintf("lambda=%.3e", meta.eigen)
            else
                gid
            end
            param_names[gid] = meta.is_sched ? "c" : "alpha"
            slugs[gid] = gid
        end
    end
    groups = NamedTuple[]
    for gid in sort(collect(keys(grouped)))
        flist = sort(grouped[gid], by = f -> parse_alpha_filename(f).param)
        push!(groups, (
            group_id=gid,
            label=labels[gid],
            slug=slugs[gid],
            param_name=param_names[gid],
            entries=[(
                param=parse_alpha_filename(f).param,
                agg_path=f,
                run_path=find_runs_csv(f),
                lambda_min=parse_alpha_filename(f).eigen,
                kappa=parse_alpha_filename(f).kappa,
                gamma=NaN,
            ) for f in flist],
        ))
    end
    return split(basename(outdir), "_")[1], groups
end

function collect_groups(outdir::AbstractString)
    manifest_rows = read_manifest(outdir)
    if manifest_rows !== nothing && !isempty(manifest_rows)
        return collect_groups_from_manifest(outdir, manifest_rows)
    end
    return collect_groups_legacy(outdir)
end

function compute_group_metrics(group)
    params = Float64[]
    ratio = Float64[]
    divergence = Float64[]
    objD = Float64[]
    objA = Float64[]
    theta = Float64[]
    files = String[]
    lambda_min = NaN
    kappa = NaN
    gamma = NaN
    T = 0
    for entry in group.entries
        push!(params, entry.param)
        firstrow, lastrow = read_aggregated_csv(entry.agg_path)
        push!(objD, lastrow.avg_vbar)
        push!(objA, lastrow.avg_vbar_A)
        push!(theta, lastrow.avg_theta_norm)
        push!(ratio, lastrow.max_avg_theta / max(lastrow.theta_star_norm, eps()))
        T = max(T, lastrow.t + 1)
        lambda_min = isfinite(lastrow.lambda_min) ? lastrow.lambda_min : entry.lambda_min
        kappa = isfinite(lastrow.kappa) ? lastrow.kappa : entry.kappa
        gamma = isfinite(lastrow.gamma) ? lastrow.gamma : entry.gamma
        if !isempty(entry.run_path) && isfile(entry.run_path)
            stats = read_run_csv(entry.run_path)
            push!(divergence, stats.divergence_rate)
        else
            push!(divergence, 0.0)
        end
        push!(files, entry.agg_path)
    end
    return (; params, ratio, divergence, objD, objA, theta, files, lambda_min, kappa, gamma, T)
end

function select_param_subset(entries)
    buckets = Dict{Int, Vector{Tuple{Float64,String}}}()
    for entry in entries
        b = floor(Int, log10(entry.param))
        push!(get!(buckets, b, Tuple{Float64,String}[]), (entry.param, entry.agg_path))
    end
    selected = Tuple{Float64,String}[]
    for key in sort(collect(keys(buckets)))
        arr = sort(buckets[key], by = x -> x[1])
        if length(arr) >= 2
            push!(selected, first(arr))
            push!(selected, last(arr))
        else
            append!(selected, arr)
        end
    end
    return sort(selected, by = x -> x[1])
end

function read_curve_downsampled(path::AbstractString, idxcol::Int; maxpoints::Int=2000)
    n = 0
    open(path, "r") do io
        _ = readline(io)
        for _ in eachline(io)
            n += 1
        end
    end
    n == 0 && return Float64[], Float64[]
    stride = max(1, cld(n, maxpoints))
    ts = Float64[]
    ys = Float64[]
    open(path, "r") do io
        _ = readline(io)
        idx = 0
        for line in eachline(io)
            if (idx % stride) == 0
                parts = split(chomp(line), ",")
                if length(parts) >= idxcol
                    t = parse(Int, parts[1])
                    y = sanitize_val(parse(Float64, parts[idxcol]))
                    if y > 0
                        push!(ts, t + 1.0)
                        push!(ys, y)
                    end
                end
            end
            idx += 1
        end
    end
    return ts, ys
end

function read_combo_curve_downsampled(path::AbstractString; maxpoints::Int=2000)
    n = 0
    open(path, "r") do io
        _ = readline(io)
        for _ in eachline(io)
            n += 1
        end
    end
    n == 0 && return Float64[], Float64[]
    stride = max(1, cld(n, maxpoints))
    ts = Float64[]
    ys = Float64[]
    open(path, "r") do io
        _ = readline(io)
        idx = 0
        for line in eachline(io)
            if (idx % stride) == 0
                parts = split(chomp(line), ",")
                y = sanitize_val(parse(Float64, parts[2]) + parse(Float64, parts[3]))
                if y > 0
                    push!(ts, parse(Int, parts[1]) + 1.0)
                    push!(ys, y)
                end
            end
            idx += 1
        end
    end
    return ts, ys
end

function representative_groups(groups; max_groups::Int=3)
    n = length(groups)
    n <= max_groups && return groups
    idxs = unique(round.(Int, range(1, n, length=max_groups)))
    return groups[idxs]
end

function plot_divergence(outdir::AbstractString)
    env_name, groups = collect_groups(outdir)
    isempty(groups) && return
    if !HAVE_PYPLOT
        println("PyPlot not available. Summary only:")
        for group in groups
            metrics = compute_group_metrics(group)
            println(short_label(group.label), " | lambda=", @sprintf("%.3e", metrics.lambda_min), " | kappa=", @sprintf("%.3e", metrics.kappa))
        end
        return
    end
    plt = plt_global
    plot_dir = joinpath(outdir, "plots")
    mkpath(plot_dir)
    for group in groups
        metrics = compute_group_metrics(group)
        fig = Base.invokelatest(plt.figure)
        fig.set_size_inches(16, 4.5)

        ax1 = Base.invokelatest(plt.subplot, 1, 3, 1)
        xr, yr = valid_xy(metrics.params, metrics.ratio)
        if !isempty(xr)
            ax1.plot(xr, clamp_vec(yr, Y_MIN_RATIO, Y_MAX_RATIO); marker="o", linewidth=1.8)
        end
        ax1.set_xscale("log")
        ax1.set_yscale("log")
        ax1.set_ylim(Y_MIN_RATIO, Y_MAX_RATIO)
        ax1.set_xlabel(group.param_name)
        ax1.set_ylabel("max E||theta||^2 / ||theta*||^2")
        ax1.grid(true, which="both", alpha=1.0)
        ax1.set_title("Ratio")

        ax2 = Base.invokelatest(plt.subplot, 1, 3, 2)
        ax2.plot(metrics.params, metrics.divergence; marker="o", linewidth=1.8, color="red")
        ax2.set_xscale("log")
        ax2.set_ylim(-0.05, 1.05)
        ax2.set_xlabel(group.param_name)
        ax2.set_ylabel("Divergence Rate")
        ax2.grid(true, which="both", alpha=1.0)
        ax2.set_title("Divergence")

        ax3 = Base.invokelatest(plt.subplot, 1, 3, 3)
        xo, yo = valid_xy(metrics.params, metrics.objA)
        if !isempty(xo)
            ax3.plot(xo, clamp_vec(yo, Y_MIN_OBJ, Y_MAX_OBJ); marker="o", linewidth=1.8, color="purple")
        end
        ax3.set_xscale("log")
        ax3.set_yscale("log")
        ax3.set_ylim(Y_MIN_OBJ, Y_MAX_OBJ)
        ax3.set_xlabel(group.param_name)
        ax3.set_ylabel("Suboptimality Gap")
        ax3.grid(true, which="both", alpha=1.0)
        ax3.set_title("Final A objective")

        cap = @sprintf("%s | lambda=%.3e | kappa=%.3e", short_label(group.label; maxlen=48), metrics.lambda_min, metrics.kappa)
        plt.suptitle(cap, fontsize=12)
        plt.tight_layout()
        outpath = joinpath(plot_dir, @sprintf("%s__final__%s.eps", env_name, slugify(group.slug)))
        _safe_savefig(plt, outpath)
        Base.invokelatest(plt.close)
        println(@sprintf("  - %s: final analysis", basename(outpath)))
    end
end

function plot_big_final_grid(outdir::AbstractString)
    env_name, groups = collect_groups(outdir)
    isempty(groups) && return
    HAVE_PYPLOT || return
    plt = plt_global
    plot_dir = joinpath(outdir, "plots")
    mkpath(plot_dir)
    nrows = length(groups)
    fig = Base.invokelatest(plt.figure)
    fig.set_size_inches(15, max(3.0 * nrows, 3.0))
    for (idx, group) in enumerate(groups)
        metrics = compute_group_metrics(group)
        ax1 = Base.invokelatest(plt.subplot, nrows, 3, (idx - 1) * 3 + 1)
        xr, yr = valid_xy(metrics.params, metrics.ratio)
        if !isempty(xr)
            ax1.plot(xr, clamp_vec(yr, Y_MIN_RATIO, Y_MAX_RATIO); marker="o", linewidth=1.5)
        end
        ax1.set_xscale("log")
        ax1.set_yscale("log")
        ax1.set_ylim(Y_MIN_RATIO, Y_MAX_RATIO)
        ax1.grid(true, which="both", alpha=1.0)
        ax1.set_ylabel(short_label(group.label; maxlen=28))
        idx == 1 && ax1.set_title("Ratio")

        ax2 = Base.invokelatest(plt.subplot, nrows, 3, (idx - 1) * 3 + 2)
        ax2.plot(metrics.params, metrics.divergence; marker="o", linewidth=1.5, color="red")
        ax2.set_xscale("log")
        ax2.set_ylim(-0.05, 1.05)
        ax2.grid(true, which="both", alpha=1.0)
        idx == 1 && ax2.set_title("Divergence")

        ax3 = Base.invokelatest(plt.subplot, nrows, 3, (idx - 1) * 3 + 3)
        xo, yo = valid_xy(metrics.params, metrics.objA)
        if !isempty(xo)
            ax3.plot(xo, clamp_vec(yo, Y_MIN_OBJ, Y_MAX_OBJ); marker="o", linewidth=1.5, color="purple")
        end
        ax3.set_xscale("log")
        ax3.set_yscale("log")
        ax3.set_ylim(Y_MIN_OBJ, Y_MAX_OBJ)
        ax3.grid(true, which="both", alpha=1.0)
        idx == 1 && ax3.set_title("Suboptimality")

        if idx == nrows
            ax1.set_xlabel(group.param_name)
            ax2.set_xlabel(group.param_name)
            ax3.set_xlabel(group.param_name)
        end
    end
    plt.tight_layout()
    outpath = joinpath(plot_dir, @sprintf("%s__finalgrid__rows-c.eps", env_name))
    _safe_savefig(plt, outpath)
    Base.invokelatest(plt.close)
    println(@sprintf("  - %s: grid summary", basename(outpath)))
end

function plot_compact_c_grid(outdir::AbstractString)
    env_name, groups = collect_groups(outdir)
    isempty(groups) && return
    HAVE_PYPLOT || return
    selected = representative_groups(groups; max_groups=3)
    plt = plt_global
    plot_dir = joinpath(outdir, "plots")
    mkpath(plot_dir)
    nrows = length(selected)
    fig = Base.invokelatest(plt.figure)
    fig.set_size_inches(15, max(3.0 * nrows, 3.0))
    for (idx, group) in enumerate(selected)
        metrics = compute_group_metrics(group)
        ax1 = Base.invokelatest(plt.subplot, nrows, 3, (idx - 1) * 3 + 1)
        xr, yr = valid_xy(metrics.params, metrics.ratio)
        if !isempty(xr)
            ax1.plot(xr, clamp_vec(yr, Y_MIN_RATIO, Y_MAX_RATIO); marker="o", linewidth=1.5)
        end
        ax1.set_xscale("log")
        ax1.set_yscale("log")
        ax1.set_ylim(Y_MIN_RATIO, Y_MAX_RATIO)
        ax1.grid(true, which="both", alpha=1.0)
        ax1.set_ylabel(short_label(group.label; maxlen=28))
        idx == 1 && ax1.set_title("Ratio")

        ax2 = Base.invokelatest(plt.subplot, nrows, 3, (idx - 1) * 3 + 2)
        ax2.plot(metrics.params, metrics.divergence; marker="o", linewidth=1.5, color="red")
        ax2.set_xscale("log")
        ax2.set_ylim(-0.05, 1.05)
        ax2.grid(true, which="both", alpha=1.0)
        idx == 1 && ax2.set_title("Divergence")

        ax3 = Base.invokelatest(plt.subplot, nrows, 3, (idx - 1) * 3 + 3)
        xo, yo = valid_xy(metrics.params, metrics.objA)
        if !isempty(xo)
            ax3.plot(xo, clamp_vec(yo, Y_MIN_OBJ, Y_MAX_OBJ); marker="o", linewidth=1.5, color="purple")
        end
        ax3.set_xscale("log")
        ax3.set_yscale("log")
        ax3.set_ylim(Y_MIN_OBJ, Y_MAX_OBJ)
        ax3.grid(true, which="both", alpha=1.0)
        idx == 1 && ax3.set_title("Suboptimality")

        if idx == nrows
            ax1.set_xlabel(group.param_name)
            ax2.set_xlabel(group.param_name)
            ax3.set_xlabel(group.param_name)
        end
    end
    plt.tight_layout()
    outpath = joinpath(plot_dir, @sprintf("%s__compact__rows-c.eps", env_name))
    _safe_savefig(plt, outpath)
    Base.invokelatest(plt.close)
    println(@sprintf("  - %s: compact grid", basename(outpath)))
end

function plot_learning_curve_grid(outdir::AbstractString)
    env_name, groups = collect_groups(outdir)
    isempty(groups) && return
    HAVE_PYPLOT || return
    plt = plt_global
    plot_dir = joinpath(outdir, "plots")
    mkpath(plot_dir)
    n = length(groups)
    ncols = max(1, ceil(Int, sqrt(n)))
    nrows = cld(n, ncols)
    cmap = Base.invokelatest(plt.get_cmap, "tab10")

    for (suffix, idxcol, ylabel_text) in (("D", 2, "D objective"), ("A", 3, "A objective"))
        fig = Base.invokelatest(plt.figure)
        fig.set_size_inches(5.0 * ncols, 3.8 * nrows)
        for (idx, group) in enumerate(groups)
            ax = Base.invokelatest(plt.subplot, nrows, ncols, idx)
            selected = select_param_subset(group.entries)
            for (j, (param, path)) in enumerate(selected)
                xs, ys = read_curve_downsampled(path, idxcol; maxpoints=try parse(Int, get(ENV, "PLOT_MAX_POINTS", "2000")) catch; 2000 end)
                if !isempty(xs)
                    color = cmap((j - 1) % 10 / 9)
                    ax.plot(xs, ys; linewidth=1.2, label=@sprintf("%s=%.2e", group.param_name, param), color=color)
                end
            end
            ax.set_yscale("log")
            ax.set_ylim(CURVE_MIN_OBJ, CURVE_MAX_OBJ)
            ax.grid(true, which="both", alpha=1.0)
            ax.set_xlabel("t")
            ax.set_title(short_label(group.label; maxlen=36), fontsize=9)
            if idx == 1
                ax.legend(loc="best", fontsize=7)
            end
        end
        plt.suptitle(@sprintf("%s learning curves (%s)", uppercase(env_name), suffix), fontsize=14)
        plt.tight_layout()
        outpath = joinpath(plot_dir, @sprintf("%s_learning_curves_grid_%s.eps", env_name, suffix))
        _safe_savefig(plt, outpath)
        Base.invokelatest(plt.close)
        println(@sprintf("  - %s: learning curves", basename(outpath)))
    end
end

function plot_best_learning_curves_by_param(outdir::AbstractString; sweeptype::Symbol=:c)
    env_name, groups = collect_groups(outdir)
    isempty(groups) && return
    HAVE_PYPLOT || return
    plt = plt_global
    plot_dir = joinpath(outdir, "plots")
    mkpath(plot_dir)
    fig = Base.invokelatest(plt.figure)
    fig.set_size_inches(9, 6)
    ax = Base.invokelatest(plt.gca)
    for group in groups
        best_path = nothing
        best_score = Inf
        for entry in group.entries
            _, lastrow = read_aggregated_csv(entry.agg_path)
            score = sanitize_val(lastrow.avg_vbar + lastrow.avg_vbar_A)
            if score < best_score
                best_score = score
                best_path = entry.agg_path
            end
        end
        best_path === nothing && continue
        xs, ys = read_combo_curve_downsampled(best_path; maxpoints=try parse(Int, get(ENV, "PLOT_MAX_POINTS", "2000")) catch; 2000 end)
        xv, yv = valid_xy(xs, ys)
        if !isempty(xv)
            ax.plot(xv, yv; linewidth=1.8, label=short_label(group.label; maxlen=32))
        end
    end
    ax.set_xscale("log")
    ax.set_yscale("log")
    ax.set_ylim(CURVE_MIN_OBJ, CURVE_MAX_OBJ)
    ax.grid(true, which="both", alpha=1.0)
    ax.set_xlabel("time steps t")
    ax.set_ylabel("best combined objective")
    ax.legend(loc="best", fontsize=8)
    plt.tight_layout()
    label = sweeptype == :alpha ? "alpha" : "c"
    outpath = joinpath(plot_dir, @sprintf("%s__bestcurves__by-%s.eps", env_name, label))
    _safe_savefig(plt, outpath)
    Base.invokelatest(plt.close)
    println(@sprintf("  - %s: best curves", basename(outpath)))
end

plot_best_learning_curves_alpha(outdir::AbstractString) = plot_best_learning_curves_by_param(outdir; sweeptype=:alpha)
plot_best_learning_curves_c(outdir::AbstractString) = plot_best_learning_curves_by_param(outdir; sweeptype=:c)

if abspath(PROGRAM_FILE) == @__FILE__
    cfg = parse_args(ARGS)
    outdir = cfg.dir
    plot_divergence(outdir)
    plot_learning_curve_grid(outdir)
    plot_big_final_grid(outdir)
    plot_compact_c_grid(outdir)
    plot_best_learning_curves_c(outdir)
end

