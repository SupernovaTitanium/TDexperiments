#!/usr/bin/env julia

include(joinpath(@__DIR__, "..", "TDThreshold.jl"))
using .TDThreshold
using Printf
using Base.Threads

const ENVS = ["toyexample", "E1", "E2", "E3", "E4", "E5", "E6", "E7", "E8", "E9", "E10"]

function parse_c_values(s::AbstractString)
    vals = Float64[]
    for tok in split(s, ",")
        t = strip(tok)
        isempty(t) && continue
        push!(vals, parse(Float64, t))
    end
    isempty(vals) && error("No c values parsed from: $s")
    return vals
end

function parse_args(args)
    n_steps = 200_000
    n_runs = 8
    c_values = [1e-5, 1e-3, 1e-1, 1.0, 1e3]
    out = "verification/julia_theory_summary.tsv"

    i = 1
    while i <= length(args)
        arg = args[i]
        if arg == "--n_steps" && i < length(args)
            n_steps = parse(Int, args[i + 1])
            i += 2
            continue
        elseif arg == "--n_runs" && i < length(args)
            n_runs = parse(Int, args[i + 1])
            i += 2
            continue
        elseif arg == "--c_values" && i < length(args)
            c_values = parse_c_values(args[i + 1])
            i += 2
            continue
        elseif arg == "--out" && i < length(args)
            out = args[i + 1]
            i += 2
            continue
        elseif arg == "--help" || arg == "-h"
            println("Usage: julia julia_theory_summary.jl [--n_steps N] [--n_runs N] [--c_values csv] [--out path]")
            exit(0)
        else
            error("Unknown or incomplete argument: $arg")
        end
    end

    return (; n_steps, n_runs, c_values, out)
end

function env_params(env_id::AbstractString)
    if env_id == "toyexample"
        return Dict("scale_factor" => "1.0")
    end
    return Dict{String,String}()
end

function summarize(cfg)
    outpath = abspath(cfg.out)
    outdir = dirname(outpath)
    isdir(outdir) || mkpath(outdir)

    open(outpath, "w") do io
        println(io, "env_id\tc\tomega\tkappa\tfinal_D\tfinal_A\tdivergence_rate")

        for env_id in ENVS
            env = TDThreshold.build_environment(env_id; params=env_params(env_id))
            metrics = TDThreshold.compute_objective_matrices(env)
            checkpoints = TDThreshold.checkpoint_indices(cfg.n_steps)
            theta0 = zeros(env.d)

            @printf("[julia] env=%s omega=%.6g kappa=%.6g\n", env_id, metrics.lambda_min, metrics.kappa)

            for cval in cfg.c_values
                runs = Vector{TDThreshold.RunResult}(undef, cfg.n_runs)
                Threads.@threads for run in 1:cfg.n_runs
                    runs[run] = TDThreshold.run_single_simulation(
                        cval,
                        run,
                        cfg.n_steps,
                        checkpoints,
                        theta0,
                        env,
                        metrics.G,
                        metrics.b,
                        metrics.c,
                        metrics.G_A,
                        metrics.b_A,
                        metrics.c_A;
                        schedule=:theory,
                        c_param=cval,
                    )
                end

                agg = TDThreshold.aggregate_results(runs, checkpoints)
                final_d = agg.avg_vbar[end]
                final_a = agg.avg_vbar_A[end]
                div_rate = agg.divergence_rate

                @printf(io, "%s\t%.12g\t%.12g\t%.12g\t%.12g\t%.12g\t%.12g\n",
                        env_id, cval, metrics.lambda_min, metrics.kappa, final_d, final_a, div_rate)
            end
        end
    end

    println("[julia] summary written to ", outpath)
end

function main()
    cfg = parse_args(ARGS)
    summarize(cfg)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
