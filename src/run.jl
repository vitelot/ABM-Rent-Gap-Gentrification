"""
    run_scenario(p::ModelParams; seed, n_thermalization = 15, n_dynamics = 170,
                 collect_quadrants = true, snapshots = Int[])

Initialise the city, thermalize it and run the gentrification dynamics.
Returns a NamedTuple with `model` (final state), `metrics` (one row per step),
`quadrants` (16 rows per step, or empty) and `snapshots` (a Dict step => deep copy
of the model at the requested steps). Step 0 is the initial state; steps
1..n_thermalization are the thermalization; the dynamics follow.
"""
function run_scenario(p::ModelParams = ModelParams(); seed::Int, n_thermalization::Int = 15,
                      n_dynamics::Int = 170, collect_quadrants::Bool = true, snapshots = Int[])
    model = initialize_model(p; seed)
    rows = NamedTuple[]
    qrows = NamedTuple[]
    saved = Dict{Int,Any}()
    record!(step) = begin
        push!(rows, step_metrics(model, step))
        collect_quadrants && append!(qrows, quadrant_counts(model, step))
        step in snapshots && (saved[step] = deepcopy(model))
    end
    record!(0)
    for s in 1:n_thermalization
        step!(model, 1)
        record!(s)
    end
    abmproperties(model).phase = :dynamics
    for s in 1:n_dynamics
        step!(model, 1)
        record!(n_thermalization + s)
    end
    metrics = DataFrame(rows)
    metrics.seed .= seed
    quadrants = collect_quadrants ? DataFrame(qrows) : DataFrame()
    collect_quadrants && (quadrants.seed .= seed)
    return (model = model, metrics = metrics, quadrants = quadrants, snapshots = saved)
end

"""
    run_multi_seed(p, seeds; kwargs...)

Run `run_scenario` for every seed (multi-threaded: start Julia with `-t auto`)
and return the concatenated `metrics` and `quadrants` tables.
"""
function run_multi_seed(p::ModelParams, seeds::AbstractVector{Int}; verbose::Bool = true, kwargs...)
    results = Vector{Any}(undef, length(seeds))
    Threads.@threads for k in eachindex(seeds)
        r = run_scenario(p; seed = seeds[k], kwargs...)
        results[k] = (metrics = r.metrics, quadrants = r.quadrants)
        verbose && println("  policy=$(p.policy) f=$(p.public_housing_fraction) seed=$(seeds[k]) done")
        flush(stdout)
    end
    metrics = reduce(vcat, [r.metrics for r in results])
    quadrants = reduce(vcat, [r.quadrants for r in results])
    return (metrics = metrics, quadrants = quadrants)
end

"Standard error of the mean, ignoring NaN."
function sem(x)
    v = filter(!isnan, collect(skipmissing(x)))
    return length(v) > 1 ? std(v) / sqrt(length(v)) : 0.0
end

"Mean ignoring NaN."
nanmean(x) = (v = filter(!isnan, collect(skipmissing(x))); isempty(v) ? NaN : mean(v))

"""
    summarize_by_step(metrics, cols; by = [:step])

Mean and SEM across seeds of the given columns, grouped by `by` (plus any extra grouping columns).
"""
function summarize_by_step(metrics::DataFrame, cols::Vector{Symbol}; by = [:step])
    pairs = Any[c => nanmean => Symbol("mean_", c) for c in cols]
    append!(pairs, Any[c => sem => Symbol("sem_", c) for c in cols])
    return combine(groupby(metrics, by), pairs...)
end

"""
    segregation_table(quadrants)

Per-step, per-seed dissimilarity and Theil indices computed from the quadrant table.
"""
function segregation_table(quadrants::DataFrame)
    rows = NamedTuple[]
    for g in groupby(quadrants, [:seed, :step])
        th = theil_decomposed(g)
        push!(rows, (seed = first(g.seed), step = first(g.step),
                     D_low_high = dissimilarity_low_high(g),
                     D_low_middle = dissimilarity(g, :n_low, :n_medium),
                     D_middle_top = dissimilarity(g, :n_medium, :n_high),
                     D_low_top = dissimilarity(g, :n_low, :n_high),
                     th...))
    end
    return DataFrame(rows)
end
