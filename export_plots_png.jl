#!/usr/bin/env julia

if length(ARGS) < 1
    error("Usage: julia export_plots_png.jl <outdir>")
end

outdir = ARGS[1]

include(joinpath(@__DIR__, "plot_divergence.jl"))

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
    if endswith(lowercase(path), ".eps")
        png_path = replace(path, r"(?i)\.eps$" => ".png")
        try
            Base.invokelatest(plt.savefig, png_path)
        catch
            # Keep EPS output even if PNG fallback fails for one file.
        end
    end
end

plot_divergence(outdir)
plot_learning_curve_grid(outdir)
if isdefined(Main, :plot_big_final_grid)
    plot_big_final_grid(outdir)
end
if isdefined(Main, :plot_compact_c_grid)
    plot_compact_c_grid(outdir)
end
if isdefined(Main, :plot_best_learning_curves_c)
    plot_best_learning_curves_c(outdir)
end
