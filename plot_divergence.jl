#!/usr/bin/env julia

using Printf
using Dates
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
    # Default to not using external LaTeX to avoid environment issues.
    use_tex = get(ENV, "PLOT_USE_TEX", "0") == "1"
    try
        plt_global.rc("text", usetex=use_tex)
        if use_tex
            plt_global.rc("font", family="serif")
            try
                plt_global.rc("text.latex.preamble", "\\usepackage{amsmath}\\usepackage{amssymb}")
            catch
            end
        end
    catch
        plt_global.rc("text", usetex=false)
    end
end

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
# Plot ranges and clamping helpers
const Y_MIN_OBJ    = 1e-6        
const Y_MAX_OBJ    = 1e12
const CURVE_MIN_OBJ = 1e-6       
const CURVE_MAX_OBJ = 1e12
const Y_MIN_RATIO  = 1e-6
const Y_MAX_RATIO  = 1e12
# Cap extremely large/invalid values when plotting to avoid Inf/NaN on log axes
const PLOT_CAP_VALUE = 1e24

const COMPACT_OMEGA_TARGETS = (2^-5, 2^4, 2^10)

function lambda_caption(lam::Float64, kappa::Float64)
    lam_str = @sprintf("%.3e", lam)
    if isfinite(kappa)
        kap_str = @sprintf("%.3e", kappa)
        latex = "\\lambda = $(lam_str),\\, \\kappa = $(kap_str)"
        plain = @sprintf("lambda=%s, kappa=%s", lam_str, kap_str)
    else
        latex = "\\lambda = $(lam_str)"
        plain = @sprintf("lambda=%s", lam_str)
    end
    return (latex=latex, plain=plain)
end


function clamp_vec(y::AbstractVector, ymin::Float64, ymax::Float64)
    out = similar(y)
    @inbounds for i in eachindex(y)
        v = y[i]
        if !isfinite(v)
            v = ymax
        end
        if v <= 0 && ymin > 0
            v = ymin
        end
        v = min(max(v, ymin), ymax)
        out[i] = v
    end
    return out
end

# Globally available sanitizer for plotting on log axes.
function sanitize_val(v::Float64)
    if !isfinite(v)
        return PLOT_CAP_VALUE
    elseif v > PLOT_CAP_VALUE
        return PLOT_CAP_VALUE
    else
        return v
    end
end

# Filter x,y pairs for log-scale plotting: keep finite and strictly positive entries.
function valid_xy(x::AbstractVector{<:Real}, y::AbstractVector{<:Real})
    n = min(length(x), length(y))
    xx = Float64[]; yy = Float64[]
    @inbounds for i in 1:n
        xi = float(x[i]); yi = float(y[i])
        yi = sanitize_val(yi)
        if isfinite(xi) && isfinite(yi) && xi > 0 && yi > 0
            push!(xx, xi)
            push!(yy, yi)
        end
    end
    return xx, yy
end

# Filter pairs by positive x and within [xmin, xmax].
function filter_xy_xrange(x::AbstractVector{<:Real}, y::AbstractVector{<:Real}, xmin::Real, xmax::Real)
    n = min(length(x), length(y))
    xx = Float64[]; yy = Float64[]
    @inbounds for i in 1:n
        xi = float(x[i]); yi = float(y[i])
        yi = sanitize_val(yi)
        if isfinite(xi) && isfinite(yi) && xi > 0 && xi >= xmin && xi <= xmax
            push!(xx, xi)
            push!(yy, yi)
        end
    end
    return xx, yy
end

function parse_alpha_filename(path::AbstractString)
    base = splitext(basename(path))[1]
    parts = split(base, "_")
    if length(parts) < 2 || parts[1] != "alpha"
        return (param=NaN, omega=NaN, eigen=NaN, kappa=NaN, is_sched=false, has_runs=false)
    end
    param = try parse(Float64, parts[2]) catch; NaN end
    omega = NaN
    eigen = NaN
    kappa = NaN
    is_sched = false
    has_runs = false
    i = 3
    while i <= length(parts)
        token = parts[i]
        if token == "runs"
            has_runs = true
            i += 1
        elseif token == "sched" && i + 1 <= length(parts) && parts[i+1] == "theory"
            is_sched = true
            i += 2
        elseif token == "omega" && i + 1 <= length(parts)
            omega = try parse(Float64, parts[i+1]) catch; NaN end
            i += 2
        elseif token == "eigen" && i + 1 <= length(parts)
            eigen = try parse(Float64, parts[i+1]) catch; NaN end
            i += 2
        elseif token == "kappa" && i + 1 <= length(parts)
            kappa = try parse(Float64, parts[i+1]) catch; NaN end
            i += 2
        else
            i += 1
        end
    end
    return (param=param, omega=omega, eigen=eigen, kappa=kappa, is_sched=is_sched, has_runs=has_runs)
end

function find_runs_csv(path::AbstractString)
    meta = parse_alpha_filename(path)
    base_dir = dirname(path)
    candidates = String[]
    if meta.is_sched
        if isfinite(meta.kappa)
            push!(candidates, @sprintf("alpha_%.2e_runs_sched_theory_omega_%.6e_eigen_%.2e_kappa_%.2e.csv", meta.param, meta.omega, meta.eigen, meta.kappa))
        end
        push!(candidates, @sprintf("alpha_%.2e_runs_sched_theory_omega_%.6e_eigen_%.2e.csv", meta.param, meta.omega, meta.eigen))
    else
        push!(candidates, @sprintf("alpha_%.2e_runs_omega_%.6e_eigen_%.2e.csv", meta.param, meta.omega, meta.eigen))
    end
    for name in candidates
        full = joinpath(base_dir, name)
        if isfile(full)
            return full
        end
    end
    return joinpath(base_dir, first(candidates))
end

function print_help()
    scr = basename(@__FILE__)
    println("""
Usage: julia $scr --dir <output_dir>

Options:
  --dir <Str>       results directory to plot (e.g., td_divergence_logs/toyexample_YYYYMMDD_HHMMSS)
  --gamma <Float>   override gamma when not in CSV (used for compact plot)
  -h, --help        show this help and exit
""")
end


function parse_args(args)
    dir = nothing
    gamma_override = nothing
    i = 1
    while i <= length(args)
        arg = args[i]
        if arg == "--help" || arg == "-h"
            print_help(); exit(0)
        elseif arg == "--dir" && i < length(args)
            dir = args[i+1]; i += 2; continue
        elseif arg == "--gamma" && i < length(args)
            gamma_override = parse(Float64, args[i+1]); i += 2; continue
        else
            @printf "Unknown or incomplete arg: %s\n" arg
            i += 1
        end
    end
    if dir === nothing
        error("Usage: julia plot_divergence.jl --dir <output_dir>")
    end
    return (dir=dir, gamma_override=gamma_override)
end


function read_aggregated_csv(path::AbstractString)
    open(path, "r") do io
        _ = readline(io) # header
        first = nothing
        last = nothing
        for line in eachline(io)
            first === nothing && (first = line)
            last = line
        end
        last === nothing && error("Empty CSV: $path")
        function parse_row(s)
            p = split(chomp(s), ",")
            len = length(p)
            len < 6 && error("Unexpected aggregated CSV format: $path")
            std_vbar      = len >= 7  ? (try parse(Float64, p[7]) catch; NaN end) : NaN
            std_vbar_A    = len >= 8  ? (try parse(Float64, p[8]) catch; NaN end) : NaN
            max_std_theta = len >= 9  ? (try parse(Float64, p[9]) catch; NaN end) : NaN
            lambda_min    = len >= 10 ? (try parse(Float64, p[10]) catch; NaN end) : NaN
            kappa         = len >= 11 ? (try parse(Float64, p[11]) catch; NaN end) : NaN
            gamma         = len >= 12 ? (try parse(Float64, p[12]) catch; NaN end) : NaN
            return (
                t=parse(Int, p[1]),
                avg_vbar=parse(Float64, p[2]),
                avg_vbar_A=parse(Float64, p[3]),
                avg_theta_norm=parse(Float64, p[4]),
                max_avg_theta=parse(Float64, p[5]),
                theta_star_norm=parse(Float64, p[6]),
                std_vbar=std_vbar,
                std_vbar_A=std_vbar_A,
                max_std_theta=max_std_theta,
                lambda_min=lambda_min,
                kappa=kappa,
                gamma=gamma
            )
        end
        return parse_row(first), parse_row(last)
    end
end

function read_run_csv(path::AbstractString)
    open(path, "r") do io
        _ = readline(io) # header
        n = 0
        div = 0
        for line in eachline(io)
            parts = split(chomp(line), ",")
            n += 1
            length(parts) >= 2 || continue
            diverged = try parse(Int, parts[2]) catch; 0 end
            div += diverged
        end
        rate = n == 0 ? 0.0 : div / n
        return (n_runs=n, divergence_rate=rate)
    end
end


function plot_divergence(outdir::AbstractString)

    files = filter(f->occursin("alpha_", f) && endswith(f, ".csv") && !occursin("_runs_", f), readdir(outdir; join=true))
    isempty(files) && error("No aggregated alpha_*.csv files found in $outdir")

    groups   = Dict{Float64, Vector{String}}()
    fallback = Dict{Float64, Vector{String}}()
    for f in files
        meta = parse_alpha_filename(f)
        if isfinite(meta.omega)
            push!(get!(groups, meta.omega, String[]), f)
        elseif isfinite(meta.eigen)
            push!(get!(fallback, meta.eigen, String[]), f)
        end
    end
    if isempty(groups)
        for (lam, flist) in fallback
            groups[lam] = flist
        end
    end

    env_name = split(basename(outdir), "_")[1]

    compute_metrics = function(flist::Vector{String})
        pairs = [(parse_alpha_filename(f).param, f) for f in flist]
        sort!(pairs, by=x->x[1])
        alphas = Float64[]
        final_vbar = Float64[]
        final_vbar_std = Float64[]
        final_vbar_A = Float64[]
        final_vbar_A_std = Float64[]
        final_theta = Float64[]
        ratio_mean = Float64[]
        ratio_std  = Float64[]
        divergence = Float64[]
        theta_star_norm = 1.0
        T = 0
        group_kappa = NaN
        group_eigen = NaN
        for (a, f) in pairs
            meta = parse_alpha_filename(f)
            push!(alphas, a)
            firstrow, lastrow = read_aggregated_csv(f)
            push!(final_vbar, lastrow.avg_vbar)
            push!(final_vbar_A, getfield(lastrow, :avg_vbar_A))
            push!(final_theta, lastrow.avg_theta_norm)
            push!(final_vbar_std, getfield(lastrow, :std_vbar))
            push!(final_vbar_A_std, getfield(lastrow, :std_vbar_A))
            theta_star_norm = lastrow.theta_star_norm
            r_mean = lastrow.max_avg_theta / max(lastrow.theta_star_norm, eps())
            r_std  = isfinite(getfield(lastrow, :max_std_theta)) ? (lastrow.max_std_theta / max(lastrow.theta_star_norm, eps())) : NaN
            push!(ratio_mean, r_mean)
            push!(ratio_std, r_std)
            T = max(T, lastrow.t + 1)
            runfile = find_runs_csv(f)
            if isfile(runfile)
                stats = read_run_csv(runfile)
                push!(divergence, stats.divergence_rate)
            else
                push!(divergence, 0.0)
            end
            if isnan(group_kappa) && isfinite(meta.kappa)
                group_kappa = meta.kappa
            end
            if isnan(group_eigen) && isfinite(meta.eigen)
                group_eigen = meta.eigen
            end
        end
        return (; alphas, final_vbar, final_vbar_std, final_vbar_A, final_vbar_A_std, final_theta,
                  ratio_mean, ratio_std, divergence, theta_star_norm, T, flist, kappa=group_kappa, eigen=group_eigen)
    end

    # If PyPlot not available, print summaries per group
    if !HAVE_PYPLOT
        @error "PyPlot not available. Install via: using Pkg; Pkg.add(\"PyPlot\")"
        println("Summary (no plots):")
        for (key, flist) in groups
            m = compute_metrics(flist)
            # Report by eigen value and condition number when available
            lam = m.eigen
            kap = m.kappa
            caption = lambda_caption(lam, kap)
            println("--- ", caption.plain, " ---")
            @printf("alpha, final_vbar, final_theta, max_avg_theta/||\\theta^*||^2, divergence_rate\n")
            for i in eachindex(m.alphas)
                @printf("%.3e, %.6g, %.6g, %.6g, %.3f\n", m.alphas[i], m.final_vbar[i], m.final_theta[i], m.ratio_mean[i], m.divergence[i])
            end
        end
        return
    end

    plt = plt_global

  
    sanitize_val(v::Float64) = !isfinite(v) ? PLOT_CAP_VALUE : (v > PLOT_CAP_VALUE ? PLOT_CAP_VALUE : v)

    valid_xy(x, y) = begin
        # sanitize y, then keep positive entries for log-y plots
        yy_s = [sanitize_val(v) for v in y]
        idx = [i for i in eachindex(yy_s) if yy_s[i] > 0 && x[i] > 0]
        xx = x[idx]
        yy = yy_s[idx]
        return xx, yy
    end

    # Subsample helper to reduce plotted points when arrays are large
    function subsample(x::AbstractVector, y::AbstractVector; maxpoints::Int=50000)
        n = length(x)
        if n <= maxpoints
            return x, y
        end
        stride = cld(n, maxpoints)
        idx = 1:stride:n
        return x[idx], y[idx]
    end

    plot_dir = joinpath(outdir, "plots"); mkpath(plot_dir)

    # Helpers for descriptive labels based on filenames
    param_key_for = function(path::AbstractString)
        base = basename(path)
        return occursin("sched_theory", base) ? "c" : "alpha"
    end

    omega_suffix = function(path::AbstractString)
        meta = parse_alpha_filename(path)
        if isfinite(meta.omega)
            return @sprintf("__omega-%.3e", meta.omega)
        else
            return ""
        end
    end

    xlabel_for = function(path::AbstractString)
        base = basename(path)
        return occursin("sched_theory", base) ? L"c" : L"\alpha"
    end

    for (key, flist) in groups
        m = compute_metrics(flist)       

        fig = Base.invokelatest(plt.figure)
        fig.set_size_inches(20, 4.5)

        # Plot 0: ratio
        ax0 = Base.invokelatest(plt.subplot, 1, 3, 1)
        x_ratio = m.alphas
        y_ratio = [min(max(sanitize_val(r), Y_MIN_RATIO), Y_MAX_RATIO) for r in m.ratio_mean]
        ax0.set_xscale("log"); ax0.set_yscale("log")
        ax0.set_xlabel(xlabel_for(m.flist[1])); ax0.set_ylabel(L"\max_{i\leq T} \, E[\| \theta_i \|^2] / \| \theta^* \|^2")
        ax0.set_ylim(Y_MIN_RATIO, Y_MAX_RATIO)
        lam = m.eigen
        kap = m.kappa
        caption = lambda_caption(lam, kap)
        caption_latex = caption.latex
        caption_plain = caption.plain
        ax0.set_title(latexstring("$(caption_latex)~\\mathrm{ratio}"))
        ax0.grid(true, alpha=1.0, which="both")

        # Plot 1: divergence rate
        ax2 = Base.invokelatest(plt.subplot, 1, 3, 2)
        xd, yd = subsample(m.alphas, m.divergence; maxpoints=parse(Int, get(ENV, "PLOT_MAX_POINTS", "50000")))
        ax2.set_xscale("log")
        ax2.set_xlabel(xlabel_for(m.flist[1])); ax2.set_ylabel("Divergence Rate")
        ax2.set_title("Probability of Divergence")
        ax2.grid(true, alpha=1.0, which="both")
        ax2.set_ylim(-0.05, 1.05)
        ax2.axhline(y=0.5, color="gray", linestyle="--", alpha=1.0)

        # Plot 3: Suboptimality gap
        ax3 = Base.invokelatest(plt.subplot, 1, 3, 3)
        xA_all, yA_all = valid_xy(m.alphas, [sanitize_val(v) for v in m.final_vbar_A])
        xA, yA = subsample(xA_all, yA_all; maxpoints=parse(Int, get(ENV, "PLOT_MAX_POINTS", "50000")))
        ax3.set_ylim(Y_MIN_OBJ, Y_MAX_OBJ)
        ax3.set_xscale("log"); ax3.set_yscale("log")
        ax3.set_xlabel(xlabel_for(m.flist[1])); ax3.set_ylabel(L"(1-\gamma)\,E[\| V_{\bar{\theta}_T} - V_{\theta^*} \|^2_D] + \gamma\,E[\| V_{\bar{\theta}_T} - V_{\theta^*} \|^2_{\mathrm{Dirichlet}}]")
        ax3.set_title("Suboptimality Gap")
        ax3.grid(true, alpha=1.0, which="both")
        is_c = occursin("sched_theory", basename(m.flist[1]))
        xmin = is_c ? 1e-8 : 1e-6
        xmax = is_c ? 1e8  : 1
        xr0, yr0 = filter_xy_xrange(x_ratio, y_ratio, xmin, xmax)
        if !isempty(xr0)
            ax0.plot(xr0, yr0; marker="o", linestyle="-", linewidth=2, markersize=6, color="blue")
        end
        xd2, yd2 = filter_xy_xrange(xd, yd, xmin, xmax)
        if !isempty(xd2)
            ax2.plot(xd2, yd2; marker="o", linestyle="-", linewidth=2, markersize=6, color="red")
        end
        xA2, yA2 = filter_xy_xrange(xA, yA, xmin, xmax)
        if !isempty(xA2)
            ax3.plot(xA2, yA2; marker="o", linestyle="-", linewidth=2, markersize=6, color="purple")
        end
        ax0.set_xlim(xmin, xmax)
        ax2.set_xlim(xmin, xmax)
        ax3.set_xlim(xmin, xmax)

        plt.suptitle(@sprintf("%s: Final Time Analysis; T=%d)", uppercase(env_name), m.T), fontsize=16)
        plt.tight_layout()
        pkey = param_key_for(m.flist[1])
        om_sfx = omega_suffix(m.flist[1])
        outpng = joinpath(plot_dir, @sprintf("%s__final__x-%s__eig-%.3e%s.eps", env_name, pkey, lam, om_sfx))
        _safe_savefig(plt, outpng)
        Base.invokelatest(plt.close)
        println()
        println("Plots saved in ", plot_dir)
        println(@sprintf("  - %s: Final analysis (3 panels) vs %s (%s)", basename(outpng), pkey, caption_plain))

        # ---- Learning curves per eigen: E[||V_theta_bar_t - V*||^2_D] vs t ----
        function select_alpha_subset(files::Vector{String})
            pairs = [(parse_alpha_filename(f).param, f) for f in files]
            sort!(pairs, by=x->x[1])
            buckets = Dict{Int, Vector{Tuple{Float64,String}}}()
            for p in pairs
                a = p[1]
                b = floor(Int, log10(a))
                push!(get!(buckets, b, Tuple{Float64,String}[]), p)
            end
            selected = Tuple{Float64,String}[]
            for b in sort(collect(keys(buckets)))
                arr = buckets[b]
                sort!(arr, by=x->x[1])
                if length(arr) >= 2
                    push!(selected, first(arr))
                    push!(selected, last(arr))
                else
                    append!(selected, arr)
                end
            end
            sort!(selected, by=x->x[1])
            return selected
        end

        function read_curve_downsampled(path::AbstractString, T::Int; maxpoints::Int=50000)
            stride = max(1, cld(T, maxpoints))
            ts = Int[]
            ys = Float64[]
            open(path, "r") do io
                _ = readline(io)
                idx = 0
                for line in eachline(io)
                    if (idx % stride) == 0
                        parts = split(chomp(line), ",")
                        t = parse(Int, parts[1])
                        y = parse(Float64, parts[2])
                        if isfinite(y) && y > 0
                            push!(ts, t)
                            push!(ys, y)
                        end
                    end
                    idx += 1
                end
            end
            return ts, ys
        end

        sel = select_alpha_subset(m.flist)
        if !isempty(sel)
            fig2 = Base.invokelatest(plt.figure)
            fig2.set_size_inches(9, 6)
            axL = Base.invokelatest(plt.subplot, 1, 1, 1)
            axL.set_title(latexstring("Learning Curves: $(caption_latex)"))
            cmap = Base.invokelatest(plt.get_cmap, "tab10")
            for (i, (a, f)) in enumerate(sel)
                ts, ys = read_curve_downsampled(f, m.T; maxpoints=parse(Int, get(ENV, "PLOT_MAX_POINTS", "200000")))
                if !isempty(ts)
                    color = cmap((i-1) % 10 / 9)
                    pname = occursin("sched_theory", basename(f)) ? "c" : "alpha"
                    axL.plot(ts, ys; linewidth=1.8, label=@sprintf("%s=%.2e", pname, a), color=color)
                end
            end
            axL.set_xlabel(L"t")
            axL.set_ylabel(L"(1-\gamma)\,E[\| \bar V_{\bar{\theta}_t} - V_{\theta^*} \|^2_D]")
            axL.set_yscale("log")
            axL.grid(true, alpha=1.0, which="both")
            axL.legend(loc="best", fontsize=8, ncol=2)
            pkey = param_key_for(m.flist[1])
            om_sfx = omega_suffix(m.flist[1])
            axL.set_ylim(CURVE_MIN_OBJ, CURVE_MAX_OBJ)
            axL.set_xlim(0, max(m.T - 1, 1))
            outpng2 = joinpath(plot_dir, @sprintf("%s__curves__obj-A=(1-gamma)D__x-t__param-%s__eig-%.3e%s.eps", env_name, pkey, lam, om_sfx))
            _safe_savefig(plt, outpng2)
            Base.invokelatest(plt.close)
            println(@sprintf("  - %s: Learning curves per eigen (<= 2 alphas per decade)", basename(outpng2)))
            figA2 = Base.invokelatest(plt.figure)
            figA2.set_size_inches(9, 6)
            axLA = Base.invokelatest(plt.subplot, 1, 1, 1)
            axLA.set_title(latexstring("Learning Curves: $(caption_latex)"))
            for (i, (a, f)) in enumerate(sel)
                tsA = Int[]; ysA = Float64[]
                open(f, "r") do io
                    _ = readline(io)
                    idx = 0
                    stride = max(1, cld(m.T, parse(Int, get(ENV, "PLOT_MAX_POINTS", "200000"))))
                    for line in eachline(io)
                        if (idx % stride) == 0
                            parts = split(chomp(line), ",")
                            if length(parts) >= 3
                                t = parse(Int, parts[1]); y = parse(Float64, parts[3])
                                if isfinite(y) && y > 0
                                    push!(tsA, t); push!(ysA, y)
                                end
                            end
                        end
                        idx += 1
                    end
                end
                if !isempty(tsA)
                    color = cmap((i-1) % 10 / 9)
                    pname = occursin("sched_theory", basename(f)) ? "c" : "alpha"
                    axLA.plot(tsA, ysA; linewidth=1.8, label=@sprintf("%s=%.2e", pname, a), color=color)
                end
            end
            axLA.set_xlabel(L"t")
            axLA.set_ylabel(L"(1-\gamma)\,E[\| V_{\bar{\theta}_T} - V_{\theta^*} \|^2_D] + \gamma\,E[\| V_{\bar{\theta}_T} - V_{\theta^*} \|^2_{\mathrm{Dirichlet}}]")
            axLA.set_yscale("log")
            axLA.grid(true, alpha=1.0, which="both")
            axLA.legend(loc="best", fontsize=8, ncol=2)
            axLA.set_ylim(Y_MIN_OBJ, Y_MAX_OBJ)
            axLA.set_xlim(0, max(m.T - 1, 1))
            outpngA2 = joinpath(plot_dir, @sprintf("%s__curves__obj-A=(1-gamma)D+gammaS__x-t__param-%s__eig-%.3e%s.eps", env_name, pkey, lam, om_sfx))
            _safe_savefig(plt, outpngA2)
            Base.invokelatest(plt.close)
            println(@sprintf("  - %s: Learning curves (A) per eigen (<= 2 alphas per decade)", basename(outpngA2)))
        end
    end
end


"""
Build a single big figure where each row corresponds to a parameter value
(alpha for alpha-sweep; c for theory-schedule) and columns are:
  1) Ratio: max E||theta||^2 / ||theta*||^2 vs eigen
  2) Divergence rate vs eigen
  3) Suboptimality gap vs eigen

Generates two figures if both alpha-sweep and c-sweep files are present.
"""
function plot_big_final_grid(outdir::AbstractString)
    !HAVE_PYPLOT && return
    plt = plt_global

    files_all = readdir(outdir; join=true)
    agg_files = filter(f->occursin("alpha_", f) && endswith(f, ".csv") && !occursin("_runs_", f) && !occursin("ratio_", f), files_all)
    isempty(agg_files) && return

    # Identify sweep type by presence of "sched_theory"
    is_c_file(f) = occursin("sched_theory", basename(f))
    groups = Dict(
        :alpha => filter(f->!is_c_file(f), agg_files),
        :c     => filter(f-> is_c_file(f), agg_files)
    )

    # Parse tokens from filenames
    function parse_tokens(path::AbstractString)
        meta = parse_alpha_filename(path)
        return meta.param, meta.omega, meta.eigen, meta.kappa, meta.is_sched
    end


    env_name = split(basename(outdir), "_")[1]
    plot_dir = joinpath(outdir, "plots"); mkpath(plot_dir)

    # Helper for linear-y filtering (keep finite y, positive x)
    function filter_posx_linear(x::Vector{Float64}, y::Vector{Float64})
        xx = Float64[]; yy = Float64[]
        @inbounds for i in eachindex(x)
            xi = x[i]; yi = y[i]
            if isfinite(xi) && xi > 0 && isfinite(yi)
                push!(xx, xi); push!(yy, yi)
            end
        end
        return xx, yy
    end

    for (sweeptype, files) in pairs(groups)
        isempty(files) && continue

        # Group aggregated files by eigenvalue
        by_lam = Dict{Float64, Vector{String}}()
        for f in files
            _, _, lam, _, _ = parse_tokens(f)
            push!(get!(by_lam, lam, String[]), f)
        end
        lams = sort(collect(keys(by_lam)))
        nrows = length(lams)
        ncols = 3
        fig = Base.invokelatest(plt.figure)
        fig.set_size_inches(5.0*ncols, max(3.2*nrows, 4.5))

        for (i, lam) in enumerate(lams)
            flist = by_lam[lam]
            meta_first = parse_alpha_filename(flist[1])
            kap = meta_first.kappa
            lam_label = @sprintf("%.3e", lam)
            if isfinite(kap)
                kap_label = @sprintf("%.3e", kap)
                row_caption = latexstring("eigen $(lam_label)\nkappa $(kap_label)")
            else
                row_caption = latexstring("eigen $(lam_label)")
            end
            # Collect series across parameter values for this eigen
            params = Float64[]; ratio = Float64[]; diver = Float64[]; objA = Float64[]
            # Sort by parameter value ascending
            sort!(flist, by = f -> (parse_tokens(f)[1]))
            for f in flist
                pval, _, _, _, _ = parse_tokens(f)
                _, last = read_aggregated_csv(f)
                r = sanitize_val(last.max_avg_theta / max(last.theta_star_norm, eps()))
                aA = sanitize_val(getfield(last, :avg_vbar_A))
                push!(params, pval)
                push!(ratio, r)
                push!(objA, aA)
                rf = find_runs_csv(f)
                if isfile(rf)
                    s = read_run_csv(rf)
                    push!(diver, s.divergence_rate)
                else
                    push!(diver, NaN)
                end
            end

            # Column 1: Ratio vs param
            ax = Base.invokelatest(plt.subplot, nrows, ncols, (i-1)*ncols + 1)
            xr, yr = valid_xy(params, ratio)
            if !isempty(xr)
                ax.plot(xr, clamp_vec(yr, Y_MIN_RATIO, Y_MAX_RATIO); marker="o", linestyle="-", linewidth=1.8, markersize=4, color="blue")
            end
            ax.set_xscale("log"); ax.set_yscale("log")
            ax.set_ylim(Y_MIN_RATIO, Y_MAX_RATIO)
            if i == 1
                ax.set_title("Ratio")
            end
            ax.set_ylabel(row_caption)

            # Column 2: Divergence vs param (linear y)
            ax2 = Base.invokelatest(plt.subplot, nrows, ncols, (i-1)*ncols + 2)
            xd, yd = filter_posx_linear(params, diver)
            if !isempty(xd)
                ax2.plot(xd, yd; marker="o", linestyle="-", linewidth=1.8, markersize=4, color="red")
            end
            ax2.set_xscale("log"); ax2.set_ylim(-0.05, 1.05)
            if i == 1
                ax2.set_title("Divergence")
            end

            # Column 3: Suboptimality gap vs param
            ax3 = Base.invokelatest(plt.subplot, nrows, ncols, (i-1)*ncols + 3)
            xA, yA = valid_xy(params, objA)
            if !isempty(xA)
                ax3.plot(xA, clamp_vec(yA, Y_MIN_OBJ, Y_MAX_OBJ); marker="o", linestyle="-", linewidth=1.8, markersize=4, color="purple")
            end
            ax3.set_xscale("log"); ax3.set_yscale("log")
            ax3.set_ylim(Y_MIN_OBJ, Y_MAX_OBJ)
            if i == 1
                ax3.set_title("Suboptimality Gap")
            end

            # Bottom row x-labels
            if i == nrows
                ax.set_xlabel(sweeptype==:c ? L"c" : L"\alpha")
                ax2.set_xlabel(sweeptype==:c ? L"c" : L"\alpha")
                ax3.set_xlabel(sweeptype==:c ? L"c" : L"\alpha")
            end
            ax.grid(true, alpha=1.0, which="both")
            ax2.grid(true, alpha=1.0, which="both")
            ax3.grid(true, alpha=1.0, which="both")

            # Per-sweep default x-limits
            xmin = sweeptype==:c ? 1e-8 : 1e-6
            xmax = sweeptype==:c ? 1e8  : 1e1
            ax.set_xlim(xmin, xmax); ax2.set_xlim(xmin, xmax); ax3.set_xlim(xmin, xmax)
        end

        plt.tight_layout()
        outpng = joinpath(plot_dir, @sprintf("%s__finalgrid__rows-%s.eps", env_name, sweeptype==:c ? "c" : "alpha"))
        _safe_savefig(plt, outpng)
        Base.invokelatest(plt.close)
        println(@sprintf("  - %s: Big final grid by eigen (%s)", basename(outpng), sweeptype==:c ? "c" : "alpha"))
    end
end

function plot_compact_c_grid(outdir::AbstractString; gamma_override::Union{Nothing,Float64}=nothing)
    if !HAVE_PYPLOT
        return
    end
    targets = (2^-4, 2^0, 2^4)
    gamma_env = get(ENV, "PLOT_GAMMA", "")
    gamma_env_val = try parse(Float64, gamma_env) catch; NaN end

    plt = plt_global
    files = filter(f->occursin("alpha_", f) && occursin("sched_theory", f) && endswith(f, ".csv") && !occursin("_runs_", f) && !occursin("ratio_", f), readdir(outdir; join=true))
    isempty(files) && return

    by_omega = Dict{Float64, Vector{String}}()
    for f in files
        meta = parse_alpha_filename(f)
        if isfinite(meta.omega)
            push!(get!(by_omega, meta.omega, String[]), f)
        end
    end
    isempty(by_omega) && return

    selected = Vector{Tuple{Float64, Vector{String}}}()
    used = Set{Float64}()
    for target in targets
        best_key = nothing
        best_gap = Inf
        target > 0 || continue
        for (omega, flist) in by_omega
            omega > 0 || continue
            gap = abs(log(target) - log(omega))
            if gap < best_gap
                best_gap = gap
                best_key = omega
            end
        end
        if best_key !== nothing && !(best_key in used)
            push!(selected, (best_key, copy(by_omega[best_key])))
            push!(used, best_key)
        end
    end

    isempty(selected) && return

    env_name = split(basename(outdir), "_")[1]
    plot_dir = joinpath(outdir, "plots"); mkpath(plot_dir)

    function filter_posx_linear(x::Vector{Float64}, y::Vector{Float64})
        xx = Float64[]; yy = Float64[]
        @inbounds for i in eachindex(x)
            xi = x[i]; yi = y[i]
            if isfinite(xi) && xi > 0 && isfinite(yi)
                push!(xx, xi); push!(yy, yi)
            end
        end
        return xx, yy
    end

    nrows = length(selected)
    ncols = 3
    fig = Base.invokelatest(plt.figure)
    fig.set_size_inches(5.0*ncols, max(2.5*nrows, 3.0))

    for (row_idx, (omega, flist)) in enumerate(selected)
        sort!(flist, by = f -> parse_alpha_filename(f).param)
        params = Float64[]; ratio = Float64[]; diver = Float64[]; objA = Float64[]
        lam = NaN; kap = NaN; gamma_val = NaN
        for f in flist
            meta = parse_alpha_filename(f)
            lam = isfinite(meta.eigen) ? meta.eigen : lam
            kap = isfinite(meta.kappa) ? meta.kappa : kap
            _, last = read_aggregated_csv(f)
            lam = isfinite(last.lambda_min) ? last.lambda_min : lam
            kap = isfinite(last.kappa) ? last.kappa : kap
            if hasproperty(last, :gamma) && isfinite(getfield(last, :gamma))
                gamma_val = getfield(last, :gamma)
            elseif gamma_override !== nothing && isfinite(gamma_override)
                gamma_val = gamma_override
            elseif isfinite(gamma_env_val)
                gamma_val = gamma_env_val
            end
            push!(params, meta.param)
            push!(ratio, sanitize_val(last.max_avg_theta / max(last.theta_star_norm, eps())))
            push!(objA, sanitize_val(getfield(last, :avg_vbar_A)))
            runfile = find_runs_csv(f)
            if isfile(runfile)
                stats = read_run_csv(runfile)
                push!(diver, stats.divergence_rate)
            else
                push!(diver, NaN)
            end
        end
        lam_label = @sprintf("%.3e", lam)
        cap =  @sprintf("%.3e", kap)

        ax_ratio = Base.invokelatest(plt.subplot, nrows, ncols, (row_idx-1)*ncols + 1)
        xr, yr = valid_xy(params, ratio)
        if !isempty(xr)
            ax_ratio.plot(xr, clamp_vec(yr, Y_MIN_RATIO, Y_MAX_RATIO); marker="o", linestyle="-", linewidth=1.8, markersize=4, color="blue")
        end
        ax_ratio.set_xscale("log"); ax_ratio.set_yscale("log")
        ax_ratio.set_ylim(Y_MIN_RATIO, Y_MAX_RATIO)
        ax_ratio.set_xlim(1e-8, 1e8)
        ax_ratio.grid(true, alpha=1.0, which="both")
        if !isfinite(gamma_val)
            error("gamma not found. Re-run td_threshold_theory_sweep.jl to include gamma column, or pass gamma_override / set PLOT_GAMMA.")
        end
        lam_display = lam / (1.0 - gamma_val)
        ax_ratio.set_ylabel(latexstring(@sprintf("\\lambda_{\\min}(\\mathbf{\\Phi}^\\top \\mathbf{D}\\mathbf{\\Phi})=%.2e", lam_display)))
        if row_idx == 1
            ax_ratio.set_title("Ratio")
        end

        ax_div = Base.invokelatest(plt.subplot, nrows, ncols, (row_idx-1)*ncols + 2)
        xd_lin, yd_lin = filter_posx_linear(params, diver)
        if !isempty(xd_lin)
            ax_div.plot(xd_lin, yd_lin; marker="o", linestyle="-", linewidth=1.8, markersize=4, color="red")
        end
        ax_div.set_xscale("log")
        ax_div.set_xlim(1e-8, 1e8)
        ax_div.set_ylim(-0.05, 1.05)
        ax_div.grid(true, alpha=1.0, which="both")
        if row_idx == 1
            ax_div.set_title("Divergence")
        end

        ax_obj = Base.invokelatest(plt.subplot, nrows, ncols, (row_idx-1)*ncols + 3)
        xA, yA = valid_xy(params, objA)
        if !isempty(xA)
            ax_obj.plot(xA, clamp_vec(yA, Y_MIN_OBJ, Y_MAX_OBJ); marker="o", linestyle="-", linewidth=1.8, markersize=4, color="purple")
        end
        ax_obj.set_xscale("log"); ax_obj.set_yscale("log")
        ax_obj.set_xlim(1e-8, 1e8)
        ax_obj.set_ylim(Y_MIN_OBJ, Y_MAX_OBJ)
        ax_obj.grid(true, alpha=1.0, which="both")
        if row_idx == 1
            ax_obj.set_title("Suboptimality Gap")
        end

        if row_idx == nrows
            ax_ratio.set_xlabel(L"c")
            ax_div.set_xlabel(L"c")
            ax_obj.set_xlabel(L"c")
        end
    end

    plt.tight_layout()
    outpng = joinpath(plot_dir, @sprintf("%s__compact__rows-c.eps", env_name))
    _safe_savefig(plt, outpng)
    Base.invokelatest(plt.close)
    println(@sprintf("  - %s: Compact c-grid", basename(outpng)))
end

function plot_learning_curve_grid(outdir::AbstractString)
    if !HAVE_PYPLOT
        @error "PyPlot not available. Install via: using Pkg; Pkg.add(\"PyPlot\")"
        return
    end

    plt = plt_global

    # Re-discover aggregated alpha files
    files = filter(f->occursin("alpha_", f) && endswith(f, ".csv") && !occursin("_runs_", f), readdir(outdir; join=true))
    isempty(files) && error("No aggregated alpha_*.csv files found in $outdir")

    # Local parser for alpha/omega/eigen from filename
    function parse_alpha_param(path)
        meta = parse_alpha_filename(path)
        return meta.param, meta.omega, meta.eigen, meta.kappa
    end

    # Select at most 2 alphas per decade bucket
    function select_alpha_subset(files::Vector{String})
        pairs = [(parse_alpha_param(f)[1], f) for f in files]
        sort!(pairs, by=x->x[1])
        buckets = Dict{Int, Vector{Tuple{Float64,String}}}()
        for p in pairs
            a = p[1]
            b = floor(Int, log10(a))
            push!(get!(buckets, b, Tuple{Float64,String}[]), p)
        end
        selected = Tuple{Float64,String}[]
        for b in sort(collect(keys(buckets)))
            arr = buckets[b]
            sort!(arr, by=x->x[1])
            if length(arr) >= 2
                push!(selected, first(arr))
                push!(selected, last(arr))
            else
                append!(selected, arr)
            end
        end
        sort!(selected, by=x->x[1])
        return selected
    end

    # Read and downsample a single curve from CSV (idxcol: 2 for D, 3 for A)
    function read_curve_downsampled(path::AbstractString, T::Int, idxcol::Int=2; maxpoints::Int=2000)
        stride = max(1, cld(T, maxpoints))
        ts = Int[]
        ys = Float64[]
        open(path, "r") do io
            _ = readline(io)
            idx = 0
            for line in eachline(io)
                if (idx % stride) == 0
                    parts = split(chomp(line), ",")
                    t = parse(Int, parts[1])
                    y = if idxcol <= length(parts)
                        try parse(Float64, parts[idxcol]) catch; NaN end
                    else
                        NaN
                    end
                    # Sanitize non-finite and overly large values to avoid dropping or infs on log plots
                    y = sanitize_val(y)
                    if y > 0
                        push!(ts, t)
                        push!(ys, y)
                    end
                end
                idx += 1
            end
        end
        return ts, ys
    end

    # Build mapping: eigen -> files and track condition numbers
    eigen_map = Dict{Float64, Vector{String}}()
    kappa_map = Dict{Float64, Float64}()
    for f in files
        _, _, lam, kap = parse_alpha_param(f)
        push!(get!(eigen_map, lam, String[]), f)
        if isfinite(kap)
            kappa_map[lam] = kap
        end
    end

    ek = sort(collect(keys(eigen_map)))
    isempty(ek) && return

    env_name = split(basename(outdir), "_")[1]
    plot_dir = joinpath(outdir, "plots"); mkpath(plot_dir)

    n = length(ek)
    ncols = max(1, ceil(Int, sqrt(n)))
    nrows = cld(n, ncols)
    fig = Base.invokelatest(plt.figure)
    fig.set_size_inches(5.0*ncols, 3.6*nrows)
    cmap = Base.invokelatest(plt.get_cmap, "tab10")

    for (idx, lam) in enumerate(ek)
        ax = Base.invokelatest(plt.subplot, nrows, ncols, idx)
        cap = lambda_caption(lam, get(kappa_map, lam, NaN))
        ax.set_title(latexstring(cap.latex), fontsize=10)
        flist = eigen_map[lam]
        _, lastrow = read_aggregated_csv(flist[1])
        T = lastrow.t + 1
        sel = select_alpha_subset(flist)
        for (i, (a, f)) in enumerate(sel)
            ts, ys = read_curve_downsampled(f, T, 2; maxpoints=parse(Int, get(ENV, "PLOT_MAX_POINTS", "200000")))
            if !isempty(ts)
                color = cmap((i-1) % 10 / 9)
                pname = occursin("sched_theory", basename(f)) ? "c" : "alpha"
                ax.plot(ts, ys; linewidth=1.2, label=@sprintf("%s=%.2e", pname, a), color=color)
            end
        end
        ax.set_yscale("log")
        ax.grid(true, alpha=1.0, which="both")
        ax.set_xlabel("t", fontsize=9)
        ax.set_ylabel(L"(1-\gamma)\,E[\| V_{\bar{\theta}_t} - V_{\theta^*} \|^2_D]", fontsize=9)
        ax.set_ylim(CURVE_MIN_OBJ, CURVE_MAX_OBJ)
        ax.set_xlim(0, max(T - 1, 1))
        if idx == 1
            ax.legend(loc="best", fontsize=7, ncol=2)
        end
    end

    plt.suptitle(@sprintf("%s: Learning Curves by Eigen", uppercase(env_name)), fontsize=14)
    plt.tight_layout()
    outpng = joinpath(plot_dir, @sprintf("%s_learning_curves_grid_D.eps", env_name))
    _safe_savefig(plt, outpng)
    Base.invokelatest(plt.close)

    # Suboptimality gap grid
    figA = Base.invokelatest(plt.figure)
    figA.set_size_inches(5.0*ncols, 3.6*nrows)
    for (idx, lam) in enumerate(ek)
        ax = Base.invokelatest(plt.subplot, nrows, ncols, idx)
        cap = lambda_caption(lam, get(kappa_map, lam, NaN))
        ax.set_title(latexstring(cap.latex), fontsize=10)
        flist = eigen_map[lam]
        _, lastrow = read_aggregated_csv(flist[1])
        T = lastrow.t + 1
        sel = select_alpha_subset(flist)
        for (i, (a, f)) in enumerate(sel)
            ts, ys = read_curve_downsampled(f, T, 3; maxpoints=parse(Int, get(ENV, "PLOT_MAX_POINTS", "200000")))
            if !isempty(ts)
                color = cmap((i-1) % 10 / 9)
                pname = occursin("sched_theory", basename(f)) ? "c" : "alpha"
                ax.plot(ts, ys; linewidth=1.2, label=@sprintf("%s=%.2e", pname, a), color=color)
            end
        end
        ax.set_yscale("log")
        ax.grid(true, alpha=1.0, which="both")
        ax.set_xlabel("t", fontsize=9)
        ax.set_ylabel(L"(1-\gamma)\,E[\| V_{\bar{\theta}_t} - V_{\theta^*} \|^2_D] + \gamma\,E[\| V_{\bar{\theta}_t} - V_{\theta^*} \|^2_{\mathrm{Dirichlet}}]", fontsize=9)
        ax.set_ylim(CURVE_MIN_OBJ, CURVE_MAX_OBJ)
        ax.set_xlim(0, max(T - 1, 1))
        if idx == 1
            ax.legend(loc="best", fontsize=7, ncol=2)
        end
    end
    plt.suptitle(@sprintf("%s: Learning Curves by Eigen (A)", uppercase(env_name)), fontsize=14)
    plt.tight_layout()
    outpngA = joinpath(plot_dir, @sprintf("%s_learning_curves_grid_A.eps", env_name))
    _safe_savefig(plt, outpngA)
    Base.invokelatest(plt.close)
    println(@sprintf("  - %s: Learning curves grid across eigen", basename(outpng)))
end

# Plot a single figure of learning curves on log-log axes where, for each eigenvalue,
# we select the best parameter (alpha or c) based on the final-time combined objective
# (1-γ)E[||V̄_T - V*||²_D] + γ E[||V̄_T - V*||²_{Dirichlet}], and draw that curve.
function plot_best_learning_curves_by_param(outdir::AbstractString; sweeptype::Symbol=:alpha)
    if !HAVE_PYPLOT
        @warn "PyPlot not available. Install via: using Pkg; Pkg.add(\"PyPlot\")"
        return
    end

    plt = plt_global

    # Discover files by sweep type
    allcsv = filter(f->endswith(f, ".csv") && !occursin("_runs_", f), readdir(outdir; join=true))
    files = if sweeptype == :alpha
        filter(f->occursin("alpha_", f) && !occursin("sched_theory", f), allcsv)
    elseif sweeptype == :c
        # theory schedule files reuse the alpha_ prefix but include "sched_theory"
        filter(f->occursin("alpha_", f) && occursin("sched_theory", f), allcsv)
    else
        error("Unknown sweeptype: $(sweeptype)")
    end
    isempty(files) && @warn "No aggregated CSV files found for $(sweeptype) in $(outdir)" && return

    # Local parsers
    parse_param_lam = function(path::AbstractString)
        base = split(basename(path), ".csv")[1]
        parts = split(base, "_")
        # pattern: alpha_<val>[_sched_theory]_omega_<val>_eigen_<lam>
        pval = parse(Float64, parts[2])
        lam  = parse(Float64, parts[end-2])
        return pval, lam
    end

    # Group by eigenvalue
    bylam = Dict{Float64, Vector{String}}()
    for f in files
        _, lam = parse_param_lam(f)
        push!(get!(bylam, lam, String[]), f)
    end

    # Choose best file per eigen based on final-time combined objective
    best_for = Dict{Float64, String}()
    for (lam, flist) in bylam
        bestf = nothing
        besty = Inf
        for f in flist
            _, last = read_aggregated_csv(f)
            y = sanitize_val(getfield(last, :avg_vbar) + getfield(last, :avg_vbar_A))
            if y < besty
                besty = y
                bestf = f
            end
        end
        if bestf !== nothing
            best_for[lam] = bestf
        end
    end
    isempty(best_for) && @warn "No best files selected for $(sweeptype) in $(outdir)" && return

    # Helper to read combined (D+A) curve with downsampling
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
        idx = 0
        open(path, "r") do io
            _ = readline(io)
            for line in eachline(io)
                if (idx % stride) == 0
                    parts = split(chomp(line), ",")
                    if length(parts) >= 3
                        t = parse(Int, parts[1])
                        yD = try parse(Float64, parts[2]) catch; NaN end
                        yA = try parse(Float64, parts[3]) catch; NaN end
                        y  = sanitize_val(yD + yA)
                        push!(ts, float(t + 1))
                        push!(ys, y)
                    end
                end
                idx += 1
            end
        end
        return ts, ys
    end

    env_name = split(basename(outdir), "_")[1]
    plot_dir = joinpath(outdir, "plots"); isdir(plot_dir) || mkpath(plot_dir)

    fig = Base.invokelatest(plt.figure)
    fig.set_size_inches(9, 6)
    ax = Base.invokelatest(plt.gca)

    # Plot one curve per eigenvalue
    for lam in sort(collect(keys(best_for)))
        f = best_for[lam]
        xs, ys = read_combo_curve_downsampled(f; maxpoints=try parse(Int, get(ENV, "PLOT_MAX_POINTS", "2000")) catch; 2000 end)
        # Filter positive for log-log
        xv = Float64[]; yv = Float64[]
        @inbounds for i in eachindex(xs)
            xi = xs[i]; yi = ys[i]
            if isfinite(xi) && isfinite(yi) && xi > 0 && yi > 0
                push!(xv, xi)
                push!(yv, yi)
            end
        end
        if !isempty(xv)
            ax.plot(xv, yv; linewidth=2.0, label=@sprintf("\u03BB=%.2e", lam))
        end
    end

    ax.set_xscale("log"); ax.set_yscale("log")
    ax.set_ylim(CURVE_MIN_OBJ, CURVE_MAX_OBJ)
    ax.grid(true, alpha=1.0, which="both")
    ax.set_xlabel(L"time\ steps\ t")
    ax.set_ylabel(L"(1-\gamma)\,\mathbb{E}[\|\bar V_T - V^*\|^2_D] + \gamma\,\mathbb{E}[\|\bar V_T - V^*\|^2_{Dirichlet}]")
    ax.legend(loc="best", fontsize=8)

    title_s = sweeptype == :alpha ? "alpha" : "c"
    plt.suptitle(@sprintf("%s: Best Learning Curves per Eigen (by %s)", uppercase(env_name), title_s), fontsize=14)
    outpng = joinpath(plot_dir, @sprintf("%s__bestcurves__by-%s.eps", env_name, title_s))
    _safe_savefig(plt, outpng)
    Base.invokelatest(plt.close)
    println(@sprintf("  - %s: Best curves by %s", basename(outpng), title_s))
end
plot_best_learning_curves_alpha(outdir::AbstractString) = plot_best_learning_curves_by_param(outdir; sweeptype=:alpha)
plot_best_learning_curves_c(outdir::AbstractString)     = plot_best_learning_curves_by_param(outdir; sweeptype=:c)

if abspath(PROGRAM_FILE) == @__FILE__
    cfg = parse_args(ARGS)
    outdir = cfg.dir
    plot_divergence(outdir)
    try
        plot_learning_curve_grid(outdir)
        if isdefined(Main, :plot_big_final_grid)
            plot_big_final_grid(outdir)
        end
        if isdefined(Main, :plot_compact_c_grid)
            plot_compact_c_grid(outdir; gamma_override=cfg.gamma_override)
        end
    catch e
        @warn "Learning-curves grid failed" exception=(e, catch_backtrace())
    end
end
