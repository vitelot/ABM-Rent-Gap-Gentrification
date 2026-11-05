# Shared preamble of the scripts: loads the model, sets output folders, parses
# `--key=value` command-line options.
const ROOT = normpath(joinpath(@__DIR__, ".."))
include(joinpath(ROOT, "src", "RentGapCity.jl"))
using .RentGapCity
using DataFrames, CSV, Statistics, Printf

const RESULTS = joinpath(ROOT, "results"); mkpath(RESULTS)
const FIGURES = joinpath(ROOT, "figures"); mkpath(FIGURES)

"Parse `--key=value` arguments into a Dict; values are kept as strings."
function parse_args(args = ARGS)
    d = Dict{String,String}()
    for a in args
        m = match(r"^--([\w\-]+)=(.*)$", a)
        m === nothing && error("bad argument $a (expected --key=value)")
        d[m[1]] = m[2]
    end
    return d
end
getarg(d, k, default) = haskey(d, k) ? parse(typeof(default), d[k]) : default
getarg(d, k, default::String) = get(d, k, default)
getarg(d, k, default::Symbol) = Symbol(get(d, k, String(default)))

"Parse a list like `1,2,3` or a range like `0:0.01:0.15`."
function parse_list(s::AbstractString, T = Float64)
    occursin(":", s) && return collect(T, eval(Meta.parse(s)))
    return [parse(T, x) for x in split(s, ",")]
end

"Seeds from `--seeds=paper` (the 15 paper seeds), `--seeds=1:20` or an explicit list."
function parse_seeds(s::AbstractString)
    s == "paper" && return PAPER_SEEDS
    return parse_list(s, Int)
end

"Add dissimilarity and Theil columns (from the quadrant table) to the metrics table."
function with_segregation(metrics::DataFrame, quadrants::DataFrame)
    isempty(quadrants) && return metrics
    seg = segregation_table(quadrants)
    return leftjoin(metrics, seg, on = [:seed, :step])
end

"Run every policy for every fraction over the seeds; returns the per-step table with segregation columns."
function run_grid(base::ModelParams, seeds, fractions, policies; n_dynamics = 170, verbose = true)
    tables = DataFrame[]
    for f in fractions, pol in policies
        p = with(base; policy = pol, public_housing_fraction = f)
        t0 = time()
        r = run_multi_seed(p, seeds; n_dynamics, verbose = false)
        t = with_segregation(r.metrics, r.quadrants)
        t.policy .= String(pol)
        t.ph_fraction .= f
        push!(tables, t)
        verbose && @printf("policy=%-8s f=%.2f  %d seeds  %.1f s\n", pol, f, length(seeds), time() - t0)
        flush(stdout)
    end
    return reduce(vcat, tables)
end
