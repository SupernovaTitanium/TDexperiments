#!/usr/bin/env julia

include(joinpath(@__DIR__, "TDThreshold.jl"))
using .TDThreshold
using LinearAlgebra
using Printf
using Base.Threads
using Base: Set
using Dates

function print_help()
    scr = basename(@__FILE__)
    println("""
Usage: julia $scr [options]

Options:
  --n_steps <Int>    total steps per run (default: 10000000)
  --n_runs  <Int>    number of runs per c (default: 48)
  --outdir  <Str>    base or explicit output directory (default: td_divergence_logs)
  --c_min <Float>    minimum c (default: 1e-8)
  --c_max <Float>    maximum c (default: 1e8)
  -h, --help         show this help and exit
""")
end

function parse_args(args)
    n_steps = 10000000
    n_runs  = 48
    outroot = "td_divergence_logs"
    c_values_str = ""
    c_min = 1e-8
    c_max = 1e8
    i = 1
    while i <= length(args)
        arg = args[i]
        if arg == "--help" || arg == "-h"
            print_help(); exit(0)
        elseif arg == "--n_steps" && i < length(args)
            n_steps = parse(Int, args[i+1]); i += 2; continue
        elseif arg == "--n_runs" && i < length(args)
            n_runs = parse(Int, args[i+1]); i += 2; continue
        elseif arg == "--outdir" && i < length(args)
            outroot = args[i+1]; i += 2; continue
        elseif arg == "--c_values" && i < length(args)
            c_values_str = args[i+1]; i += 2; continue
        elseif arg == "--c_min" && i < length(args)
            c_min = parse(Float64, args[i+1]); i += 2; continue
        elseif arg == "--c_max" && i < length(args)
            c_max = parse(Float64, args[i+1]); i += 2; continue
        else
            @printf "Unknown or incomplete arg: %s\n" arg
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
            for m in (0.0, 1/6,2/6,3/6,4/6,5/6)
                v = 10.0^m * 10.0^k
                if v >= c_min * (1 - 1e-12) && v <= c_max * (1 + 1e-12)
                    push!(cvals, v)
                end
            end
        end
        sort!(unique!(cvals))
    end
    return (n_steps=n_steps, n_runs=n_runs, outroot=outroot, c_values=cvals)
end




function main()
    cfg = parse_args(ARGS)
    env_name = "toyexample"
    base = cfg.outroot
    if startswith(basename(base), string(env_name, "_"))
        outdir = base
    else
        ts = Dates.format(now(), "yyyymmdd_HHMMSS")
        outdir = joinpath(base, string(env_name, "_", ts))
    end
    isdir(outdir) || mkpath(outdir)

    @printf "Using %d threads\n" Threads.nthreads()

    # Omegas like original sweep
    omegas=Float64[]
    for k in [-10,-8,-6,-4,-2,0,2,4,6,8,10]
        push!(omegas, 2.0^k)
    end    


    for omega in omegas
        ref = TDThreshold.ToyExampleMDP(gamma=0.99, seed=114514, scale_factor=omega)

        # Build A1=(1-γ)D and A2=A1+γS
        Dm = Diagonal(ref.D)
        Pm = ref.P
        S = Dm - 0.5 * (Dm*Pm + transpose(Pm)*Dm)
        A1 = (1.0 - ref.gamma) * Dm
        A2 = A1 + ref.gamma * S

        G = transpose(ref.Phi) * (A1 * ref.Phi)
        b = transpose(ref.Phi) * (A1 * ref.V_star)
        c = dot(ref.V_star, A1 * ref.V_star)

        G2 = transpose(ref.Phi) * (A2 * ref.Phi)
        b2 = transpose(ref.Phi) * (A2 * ref.V_star)
        c2 = dot(ref.V_star, A2 * ref.V_star)

        lam = minimum(eigvals(Symmetric(G)))
        kappa = maximum(eigvals(Symmetric(G))) / lam
        @printf "Testing omega=%.3e (λmin=%.3e, κ=%.3e)\n" omega lam kappa

        theta_star_sq = dot(ref.theta_star, ref.theta_star)
        theta0 = zeros(ref.d)

        # Sweep c values
        for cval in cfg.c_values
            @printf "  c=%.3e (theory schedule) ...\n" cval
            runs = Vector{TDThreshold.RunResult}(undef, cfg.n_runs)
            Threads.@threads for run in 1:cfg.n_runs
                runs[run] = TDThreshold.run_single_simulation(cval, run, cfg.n_steps, theta0, ref, G, b, c, G2, b2, c2; schedule=:theory, c_param=cval)
            end

            agg = TDThreshold.aggregate_results(runs, cfg.n_steps)

            # Aggregated CSV (6 columns)
            aggfile = joinpath(outdir, @sprintf("alpha_%.2e_sched_theory_omega_%.6e_eigen_%.2e_kappa_%.2e.csv", cval, omega, lam, kappa))
            open(aggfile, "w") do io
                println(io, "timestep,E_D[||Vbar_t - V*||^2],E_A[||Vbar_t - V*||^2],E[||theta_t||^2],max_i<=T ||theta_i||^2,||theta^*||^2,std_D,std_A,std_max_theta,lambda_min,kappa")       
                t_temp=100      
                for t in 1:cfg.n_steps
                    if t<=100
                        @printf(io, "%d,%.12g,%.12g,%.12g,%.12g,%.12g,%.12g,%.12g,%.12g,%.12g,%.12g\n", t, agg.avg_vbar[t], agg.avg_vbar_A[t], agg.avg_theta_norms[t], agg.max_avg_theta, theta_star_sq, agg.std_vbar[t], agg.std_vbar_A[t], agg.max_std_theta, lam, kappa)
                    else 
                        if t > t_temp*10^0.01
                            @printf(io, "%d,%.12g,%.12g,%.12g,%.12g,%.12g,%.12g,%.12g,%.12g,%.12g,%.12g\n", t, agg.avg_vbar[t], agg.avg_vbar_A[t], agg.avg_theta_norms[t], agg.max_avg_theta, theta_star_sq, agg.std_vbar[t], agg.std_vbar_A[t], agg.max_std_theta, lam, kappa)
                            t_temp = t
                        end
                    end
                end
            end

            # Per-run CSV

            temp_check= 100        
            runfile = joinpath(outdir, @sprintf("alpha_%.2e_runs_sched_theory_omega_%.6e_eigen_%.2e_kappa_%.2e.csv", cval, omega, lam, kappa))
            open(runfile, "w") do io
                println(io, "run_idx,diverged,diverged_at,(1-\\gamma)E[||\\bar V_T - V^*||^2_D],(1-\\gamma)E[||\\bar V_T - V^*||^2_D]+\\gamma E[||\\bar V_T - V^*||^2_{Dirichlet}],final_theta_norm,max_theta_norm,ratio_max_over_theta_star,theta_star_norm")
                for r in runs
                    ratio = r.max_theta_norm / theta_star_sq
                    @printf(io, "%d,%d,%d,%.12g,%.12g,%.12g,%.12g,%.12g,%.12g\n", r.run_idx, r.diverged ? 1 : 0, r.diverged_at, r.final_vbar, r.final_vbar_A, r.final_theta_norm, r.max_theta_norm, ratio, theta_star_sq)      
                end
            end

            # Console summaries (selected subset)
            for r in runs
                ratio = r.max_theta_norm / theta_star_sq
                if r.diverged
                    @printf "Run %d/%d: DIVERGED at step %d | (1-\\gamma)\\mathbb{E}[||\\bar V_T - V^*||^2_D]=%.6g, (1-\\gamma)\\mathbb{E}[||\\bar V_T - V^*||^2_D]+\\gamma \\mathbb{E}[||\\bar V_T - V^*||^2_{Dirichlet}]=%.6g, ||\\theta_T||^2=%.6g, \\max||\\theta||^2=%.6g, ||\\theta^*||^2=%.6g, ratio=%.6g\n" r.run_idx cfg.n_runs r.diverged_at r.final_vbar r.final_vbar_A r.final_theta_norm r.max_theta_norm theta_star_sq ratio
                else
                    @printf "Run %d/%d: converged | (1-\\gamma)\\mathbb{E}[||\\bar V_T - V^*||^2_D]=%.6g, (1-\\gamma)\\mathbb{E}[||\\bar V_T - V^*||^2_D]+\\gamma \\mathbb{E}[||\\bar V_T - V^*||^2_{Dirichlet}]=%.6g, ||\\theta_T||^2=%.6g, \\max||\\theta||^2=%.6g, ||\\theta^*||^2=%.6g, ratio=%.6g\n" r.run_idx cfg.n_runs r.final_vbar r.final_vbar_A r.final_theta_norm r.max_theta_norm theta_star_sq ratio
                end
            end
        end
        # Ratio CSV across c
        ratiofile = joinpath(outdir, @sprintf("ratio_omega_%.6e_eigen_%.2e_kappa_%.2e.csv", omega, lam, kappa))
        open(ratiofile, "w") do io
            println(io, "eigen,param,max_i<=T ||theta_i||^2/||theta^*||^2")
            for cval in cfg.c_values
                # read first row to get max_avg_theta and theta_star from aggregated file
                aggfile = joinpath(outdir, @sprintf("alpha_%.2e_sched_theory_omega_%.6e_eigen_%.2e_kappa_%.2e.csv", cval, omega, lam, kappa))
                open(aggfile, "r") do aio
                    _ = readline(aio)
                    first = readline(aio)
                    parts = split(chomp(first), ",")
                    max_avg_theta = parse(Float64, parts[5])
                    @printf(io, "%.12g,%.12g,%.12g,%.12g\n", lam, kappa, cval, max_avg_theta / theta_star_sq)
                end
            end
        end
    end

    # Plot synchronously (avoid world-age via invokelatest)
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

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
