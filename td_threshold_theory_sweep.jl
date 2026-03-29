#!/usr/bin/env julia

include(joinpath(@__DIR__, "TDThreshold.jl"))
using .TDThreshold
using Printf
using Base.Threads
using Dates

function print_help()
    scr = basename(@__FILE__)
    println("""
Usage: julia $scr [options]

Options:
  --env <Str>           environment id (default: toyexample)
  --n_steps <Int>       total steps per run (default: 10000000)
  --n_runs <Int>        number of runs per parameter value (default: 48)
  --outdir <Str>        base or explicit output directory (default: td_divergence_logs)
  --set <key=value>     fixed environment parameter; repeatable
  --sweep <k=v1,v2>     sweep an environment parameter; repeatable
  --c_values <csv>      explicit theory-schedule c values
  --c_min <Float>       minimum c when auto-generating values (default: 1e-8)
  --c_max <Float>       maximum c when auto-generating values (default: 1e8)
  --skip_plots          write CSV/manifest only
  -h, --help            show this help and exit

Examples:
  julia $scr --env E4 --set eps1=1e-3 --sweep eps2=1e-1,1e-2,1e-3 --set reward_mode=signed
  julia $scr --env E9 --set m=64 --set alpha_max=1.57079632679 --sweep eps1=1e-2,1e-3
""")
    println("Available environments: ", join(TDThreshold.available_environment_ids(), ", "))
end

function parse_key_value(spec::AbstractString)
    idx = findfirst(==( '=' ), spec)
    idx === nothing && error("Expected key=value, got: $spec")
    key = strip(spec[1:prevind(spec, idx)])
    val = strip(spec[nextind(spec, idx):end])
    isempty(key) && error("Empty key in spec: $spec")
    isempty(val) && error("Empty value in spec: $spec")
    return key => val
end

function parse_args(args)
    env_id = "toyexample"
    n_steps = 10_000_000
    n_runs = 48
    outroot = "td_divergence_logs"
    c_values_str = ""
    c_min = 1e-8
    c_max = 1e8
    set_params = Dict{String,String}()
    sweep_params = Dict{String,Vector{String}}()
    skip_plots = false

    i = 1
    while i <= length(args)
        arg = args[i]
        if arg == "--help" || arg == "-h"
            print_help()
            exit(0)
        elseif arg == "--env" && i < length(args)
            env_id = args[i + 1]
            i += 2
            continue
        elseif arg == "--n_steps" && i < length(args)
            n_steps = parse(Int, args[i + 1])
            i += 2
            continue
        elseif arg == "--n_runs" && i < length(args)
            n_runs = parse(Int, args[i + 1])
            i += 2
            continue
        elseif arg == "--outdir" && i < length(args)
            outroot = args[i + 1]
            i += 2
            continue
        elseif arg == "--c_values" && i < length(args)
            c_values_str = args[i + 1]
            i += 2
            continue
        elseif arg == "--c_min" && i < length(args)
            c_min = parse(Float64, args[i + 1])
            i += 2
            continue
        elseif arg == "--c_max" && i < length(args)
            c_max = parse(Float64, args[i + 1])
            i += 2
            continue
        elseif arg == "--set" && i < length(args)
            key, val = parse_key_value(args[i + 1])
            set_params[key] = val
            i += 2
            continue
        elseif arg == "--sweep" && i < length(args)
            key, val = parse_key_value(args[i + 1])
            sweep_params[key] = [strip(tok) for tok in split(val, ",") if !isempty(strip(tok))]
            i += 2
            continue
        elseif arg == "--skip_plots"
            skip_plots = true
            i += 1
            continue
        else
            @printf("Unknown or incomplete arg: %s\n", arg)
            i += 1
        end
    end

    cvals = Float64[]
    if !isempty(c_values_str)
        for tok in split(c_values_str, ",")
            push!(cvals, parse(Float64, strip(tok)))
        end
    else
        lo = floor(Int, log10(c_min))
        hi = ceil(Int, log10(c_max))
        for k in lo:hi
            for m in (0.0, 1 / 6, 2 / 6, 3 / 6, 4 / 6, 5 / 6)
                v = 10.0^m * 10.0^k
                if v >= c_min * (1 - 1e-12) && v <= c_max * (1 + 1e-12)
                    push!(cvals, v)
                end
            end
        end
        sort!(unique!(cvals))
    end

    return (; env_id, n_steps, n_runs, outroot, c_values=cvals, set_params, sweep_params, skip_plots)
end

function parameter_product(base::Dict{String,String}, sweeps::Dict{String,Vector{String}})
    sweep_keys = sort(collect(Base.keys(sweeps)))
    cases = Dict{String,String}[]
    function recur(idx::Int, current::Dict{String,String})
        if idx > length(sweep_keys)
            push!(cases, copy(current))
            return
        end
        key = sweep_keys[idx]
        for val in sweeps[key]
            current[key] = val
            recur(idx + 1, current)
        end
        delete!(current, key)
    end
    current = copy(base)
    if isempty(sweep_keys)
        push!(cases, current)
    else
        recur(1, current)
    end
    return cases
end

function build_case_parameters(env_id::AbstractString, set_params::Dict{String,String}, sweep_params::Dict{String,Vector{String}})
    conflicts = intersect(Set(keys(set_params)), Set(keys(sweep_params)))
    isempty(conflicts) || error("Parameters cannot appear in both --set and --sweep: $(join(sort(collect(conflicts)), ", "))")

    sweeps = copy(sweep_params)
    if isempty(sweeps)
        defaults = TDThreshold.default_environment_sweeps(env_id)
        if !isempty(defaults)
            for (k, vals) in defaults
                if !haskey(set_params, k)
                    sweeps[k] = vals
                end
            end
        end
    end
    return parameter_product(set_params, sweeps)
end

function sanitize_token(s::AbstractString)
    x = lowercase(strip(String(s)))
    x = replace(x, ' ' => '-', ',' => '-', ';' => '-', '/' => '-', '\\' => '-', '(' => '-', ')' => '-', '[' => '-', ']' => '-')
    x = replace(x, "--" => "-")
    return strip(x, '-')
end

function case_label(env)
    parts = String[]
    for key in sort(collect(keys(env.metadata)))
        push!(parts, string(key, "=", env.metadata[key]))
    end
    isempty(parts) && return env.display_name
    return string(env.display_name, " | ", join(parts, " | "))
end

function case_slug(env, case_id::AbstractString)
    parts = [sanitize_token(env.env_id), string("case-", case_id)]
    for key in sort(collect(keys(env.metadata)))
        push!(parts, string(sanitize_token(key), "-", sanitize_token(env.metadata[key])))
    end
    return join(parts, "__")
end

function serialize_metadata(env)
    pairs = String[]
    for key in sort(collect(keys(env.metadata)))
        push!(pairs, string(key, "=", env.metadata[key]))
    end
    return join(pairs, ";")
end

function write_aggregated_csv(path::AbstractString, agg, n_steps::Int, lambda_min::Float64, kappa::Float64, gamma::Float64, theta_star_sq::Float64)
    isempty(agg.timesteps) && error("No checkpoint rows available for $path")
    agg.timesteps[end] == n_steps || error("Final checkpoint $(agg.timesteps[end]) does not match n_steps=$n_steps")
    open(path, "w") do io
        println(io, "timestep,E_D[||Vbar_t - V*||^2],E_A[||Vbar_t - V*||^2],E[||theta_t||^2],max_i<=T ||theta_i||^2,||theta^*||^2,std_D,std_A,std_max_theta,lambda_min,kappa,gamma")
        for (idx, t) in enumerate(agg.timesteps)
            @printf(io, "%d,%.12g,%.12g,%.12g,%.12g,%.12g,%.12g,%.12g,%.12g,%.12g,%.12g,%.12g\n",
                    t, agg.avg_vbar[idx], agg.avg_vbar_A[idx], agg.avg_theta_norms[idx], agg.max_avg_theta,
                    theta_star_sq, agg.std_vbar[idx], agg.std_vbar_A[idx], agg.max_std_theta, lambda_min, kappa, gamma)
        end
    end
end

function write_run_csv(path::AbstractString, runs, theta_star_sq::Float64)
    open(path, "w") do io
        println(io, "run_idx,diverged,diverged_at,(1-\\gamma)E[||\\bar V_T - V^*||^2_D],(1-\\gamma)E[||\\bar V_T - V^*||^2_D]+\\gamma E[||\\bar V_T - V^*||^2_{Dirichlet}],final_theta_norm,max_theta_norm,ratio_max_over_theta_star,theta_star_norm")
        for r in runs
            ratio = r.max_theta_norm / max(theta_star_sq, eps())
            @printf(io, "%d,%d,%d,%.12g,%.12g,%.12g,%.12g,%.12g,%.12g\n",
                    r.run_idx, r.diverged ? 1 : 0, r.diverged_at, r.final_vbar, r.final_vbar_A,
                    r.final_theta_norm, r.max_theta_norm, ratio, theta_star_sq)
        end
    end
end

function write_ratio_csv(path::AbstractString, rows)
    open(path, "w") do io
        println(io, "param,max_i<=T ||theta_i||^2/||theta^*||^2")
        for row in rows
            @printf(io, "%.12g,%.12g\n", row.param, row.ratio)
        end
    end
end

function main()
    cfg = parse_args(ARGS)
    env_id = TDThreshold.canonical_env_id(cfg.env_id)
    checkpoints = TDThreshold.checkpoint_indices(cfg.n_steps)
    base = cfg.outroot
    if startswith(basename(base), string(env_id, "_"))
        outdir = base
    else
        ts = Dates.format(now(), "yyyymmdd_HHMMSS")
        outdir = joinpath(base, string(env_id, "_", ts))
    end
    isdir(outdir) || mkpath(outdir)

    @printf("Using %d threads\n", Threads.nthreads())
    @printf("Environment: %s\n", env_id)

    case_params = build_case_parameters(env_id, cfg.set_params, cfg.sweep_params)
    isempty(case_params) && error("No environment cases to run")
    @printf("Cases: %d | c-values: %d\n", length(case_params), length(cfg.c_values))

    manifest_path = joinpath(outdir, "manifest.tsv")
    open(manifest_path, "w") do manifest_io
        println(manifest_io, join([
            "case_id", "env_id", "case_slug", "case_label", "param_name", "param_value",
            "agg_file", "run_file", "lambda_min", "kappa", "gamma", "theta_star_norm", "metadata"
        ], '\t'))

        for (case_index, params) in enumerate(case_params)
            env = TDThreshold.build_environment(env_id; params=params)
            metrics = TDThreshold.compute_objective_matrices(env)
            theta0 = zeros(env.d)
            cid = lpad(string(case_index), 4, '0')
            slug = case_slug(env, cid)
            label = case_label(env)
            lambda_min = metrics.lambda_min
            kappa = metrics.kappa
            theta_star_sq = metrics.theta_star_sq
            metadata_str = serialize_metadata(env)
            ratio_rows = NamedTuple{(:param, :ratio),Tuple{Float64,Float64}}[]

            @printf("Case %s: %s\n", cid, label)
            @printf("  lambda_min=%.3e, kappa=%.3e\n", lambda_min, kappa)

            for cval in cfg.c_values
                @printf("  c=%.3e ...\n", cval)
                runs = Vector{TDThreshold.RunResult}(undef, cfg.n_runs)
                Threads.@threads for run in 1:cfg.n_runs
                    runs[run] = TDThreshold.run_single_simulation(cval, run, cfg.n_steps, checkpoints, theta0, env,
                        metrics.G, metrics.b, metrics.c, metrics.G_A, metrics.b_A, metrics.c_A;
                        schedule=:theory, c_param=cval)
                end

                agg = TDThreshold.aggregate_results(runs, checkpoints)
                agg_name = @sprintf("alpha_%.2e_sched_theory_case_%s.csv", cval, cid)
                run_name = @sprintf("alpha_%.2e_runs_sched_theory_case_%s.csv", cval, cid)
                agg_path = joinpath(outdir, agg_name)
                run_path = joinpath(outdir, run_name)
                write_aggregated_csv(agg_path, agg, cfg.n_steps, lambda_min, kappa, env.gamma, theta_star_sq)
                write_run_csv(run_path, runs, theta_star_sq)

                ratio = agg.max_avg_theta / max(theta_star_sq, eps())
                push!(ratio_rows, (param=cval, ratio=ratio))

                println(manifest_io, join([
                    cid,
                    env.env_id,
                    slug,
                    label,
                    "c",
                    @sprintf("%.16g", cval),
                    agg_name,
                    run_name,
                    @sprintf("%.16g", lambda_min),
                    @sprintf("%.16g", kappa),
                    @sprintf("%.16g", env.gamma),
                    @sprintf("%.16g", theta_star_sq),
                    metadata_str,
                ], '\t'))
            end

            ratio_name = @sprintf("ratio_case_%s.tsv", cid)
            write_ratio_csv(joinpath(outdir, ratio_name), ratio_rows)
        end
    end

    if !cfg.skip_plots
        try
            include(joinpath(@__DIR__, "plot_divergence.jl"))
            if isdefined(Main, :plot_divergence)
                Base.invokelatest(getfield(Main, :plot_divergence), outdir)
            end
            if isdefined(Main, :plot_learning_curve_grid)
                Base.invokelatest(getfield(Main, :plot_learning_curve_grid), outdir)
            end
            if isdefined(Main, :plot_big_final_grid)
                Base.invokelatest(getfield(Main, :plot_big_final_grid), outdir)
            end
            if isdefined(Main, :plot_compact_c_grid)
                Base.invokelatest(getfield(Main, :plot_compact_c_grid), outdir)
            end
            if isdefined(Main, :plot_best_learning_curves_c)
                Base.invokelatest(getfield(Main, :plot_best_learning_curves_c), outdir)
            end
        catch e
            @warn "Plotting failed (install PyPlot and retry)" exception=(e, catch_backtrace())
            @info "Re-run plotting: julia plot_divergence.jl --dir $(outdir)"
        end
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end


