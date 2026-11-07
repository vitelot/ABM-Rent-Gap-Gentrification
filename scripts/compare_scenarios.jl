# Time evolution under the three scenarios (free market, random, rent-gap) at a fixed
# public housing fraction, averaged over the seeds: median income, population flows,
# segregation indices, three-tier dissimilarity and Theil decomposition
# (Figs. "inner city comparisons", "segregation indices", "three_tier", "theil").
#
#   julia +1.10 -t auto --project scripts/compare_scenarios.jl --fraction=0.07 --tag=paper
include(joinpath(@__DIR__, "common.jl"))
using CairoMakie

args = parse_args()
tag = getarg(args, "tag", "paper")
f = getarg(args, "fraction", 0.07)
seeds = parse_seeds(getarg(args, "seeds", "paper"))
n_dynamics = getarg(args, "steps", 170)
n_therm = 15
base = ModelParams(
    public_housing_spillover = getarg(args, "spillover", 2.0),
    public_housing_spillover_mode = getarg(args, "mode", :once),
)

scenarios = [("none", with(base; policy = :none)),
             ("random", with(base; policy = :random, public_housing_fraction = f)),
             ("rentgap", with(base; policy = :rentgap, public_housing_fraction = f)),
             ("rentgap_0.06", with(base; policy = :rentgap, public_housing_fraction = 0.06)),
             ("rentgap_0.10", with(base; policy = :rentgap, public_housing_fraction = 0.10))]

tables = DataFrame[]
for (name, p) in scenarios
    t0 = time()
    r = run_multi_seed(p, seeds; n_dynamics, verbose = false)
    t = with_segregation(r.metrics, r.quadrants)
    t.scenario .= name
    push!(tables, t)
    @printf("%-14s %d seeds  %.1f s\n", name, length(seeds), time() - t0); flush(stdout)
end
steps = reduce(vcat, tables)
CSV.write(joinpath(RESULTS, "compare_$(tag)_steps.csv"), steps)

cols = [:median_income_inner_city, :median_inner_city_rent, :n_low_inner, :n_high_inner,
        :neighbour_segregation_index, :D_low_high, :D_low_middle, :D_middle_top, :D_low_top,
        :H_total, :H_between, :H_within_inner, :H_within_suburbs, :n_renovations_inner, :lcc_gentrification]
summ = summarize_by_step(steps, cols; by = [:scenario, :step])
CSV.write(joinpath(RESULTS, "compare_$(tag)_summary.csv"), summ)

# ---- investment intensity in the inner city (text of the paper) ------------------
println("\nInner-city renovations per step after the policy activation step (mean over seeds):")
for name in ("none", "random", "rentgap")
    d = steps[steps.scenario .== name, :]
    # activation step of each seed under rent-gap, used as reference for all three
    act = combine(groupby(steps[steps.scenario .== "rentgap", :], :seed),
                  [:step, :public_housing_active] => ((s, a) -> any(a) ? minimum(s[a]) : n_therm) => :t_act)
    rates = Float64[]
    for row in eachrow(act)
        dd = d[(d.seed .== row.seed) .& (d.step .> row.t_act), :]
        push!(rates, mean(dd.n_renovations_inner))
    end
    @printf("  %-8s %.2f\n", name, mean(rates))
end

# ---- figures ------------------------------------------------------------------
sc_colors = Dict("none" => :seagreen, "random" => :dodgerblue3, "rentgap" => :darkorange2,
                 "rentgap_0.06" => :firebrick, "rentgap_0.10" => :purple)
sc_labels = Dict("none" => "No intervention", "random" => "Random PH (f=$f)", "rentgap" => "Rent-gap PH (f=$f)",
                 "rentgap_0.06" => "Rent-gap PH (f=0.06)", "rentgap_0.10" => "Rent-gap PH (f=0.10)")

function curve!(ax, summ, scenario, col; color = sc_colors[scenario], label = sc_labels[scenario], linestyle = :solid)
    d = sort(summ[summ.scenario .== scenario, :], :step)
    m = d[!, Symbol("mean_", col)]; s = d[!, Symbol("sem_", col)]
    band!(ax, d.step, m .- s, m .+ s, color = (color, 0.2))
    lines!(ax, d.step, m; color, label, linestyle, linewidth = 2)
end

# (a) median income, (b) agents
fig = Figure(size = (1000, 400))
ax1 = Axis(fig[1, 1], xlabel = "Step", ylabel = "Inner-city median income")
for sc in ("none", "random", "rentgap"); curve!(ax1, summ, sc, :median_income_inner_city); end
vlines!(ax1, [n_therm], color = :black, linestyle = :dash)
axislegend(ax1, position = :lt)
ax2 = Axis(fig[1, 2], xlabel = "Step", ylabel = "Agents in the inner city")
for (sc, ls) in (("none", :solid), ("random", :dash), ("rentgap", :dot))
    curve!(ax2, summ, sc, :n_low_inner; color = :dodgerblue3, label = "Low income, $(sc_labels[sc])", linestyle = ls)
    curve!(ax2, summ, sc, :n_high_inner; color = :firebrick, label = "High income, $(sc_labels[sc])", linestyle = ls)
end
vlines!(ax2, [n_therm], color = :black, linestyle = :dash)
axislegend(ax2, position = :lt, labelsize = 9)
save(joinpath(FIGURES, "inner_city_comparison_$(tag).pdf"), fig)
# single panels for the manuscript
let f1 = Figure(size = (520, 400))
    ax = Axis(f1[1, 1], xlabel = "Step", ylabel = "Inner-city median income")
    for sc in ("none", "random", "rentgap"); curve!(ax, summ, sc, :median_income_inner_city); end
    vlines!(ax, [n_therm], color = :black, linestyle = :dash); axislegend(ax, position = :lt)
    save(joinpath(FIGURES, "median_income_comparison_$(tag).pdf"), f1)
end
let f1 = Figure(size = (520, 400))
    ax = Axis(f1[1, 1], xlabel = "Step", ylabel = "Agents in the inner city")
    for (sc, ls) in (("none", :solid), ("random", :dash), ("rentgap", :dot))
        curve!(ax, summ, sc, :n_low_inner; color = :dodgerblue3, label = "Low income, $(sc_labels[sc])", linestyle = ls)
        curve!(ax, summ, sc, :n_high_inner; color = :firebrick, label = "High income, $(sc_labels[sc])", linestyle = ls)
    end
    vlines!(ax, [n_therm], color = :black, linestyle = :dash); axislegend(ax, position = :lt, labelsize = 8)
    save(joinpath(FIGURES, "number_agents_$(tag).pdf"), f1)
end

# segregation indices: free, rent-gap 0.06, rent-gap 0.10
fig = Figure(size = (1000, 400))
ax1 = Axis(fig[1, 1], xlabel = "Step", ylabel = "Neighbour segregation index")
ax2 = Axis(fig[1, 2], xlabel = "Step", ylabel = "Dissimilarity index (low vs high)")
for sc in ("none", "rentgap_0.06", "rentgap_0.10")
    curve!(ax1, summ, sc, :neighbour_segregation_index)
    curve!(ax2, summ, sc, :D_low_high)
end
axislegend(ax1, position = :lt); axislegend(ax2, position = :lt)
save(joinpath(FIGURES, "segregation_indices_$(tag).pdf"), fig)
for (col, ylab, name) in ((:neighbour_segregation_index, "Neighbour segregation index", "neighbor_segregation"),
                          (:D_low_high, "Dissimilarity index (low vs high)", "dissimilarity_index"))
    f1 = Figure(size = (520, 400))
    ax = Axis(f1[1, 1], xlabel = "Step", ylabel = ylab)
    for sc in ("none", "rentgap_0.06", "rentgap_0.10"); curve!(ax, summ, sc, col); end
    axislegend(ax, position = :lt)
    save(joinpath(FIGURES, "$(name)_$(tag).pdf"), f1)
end

# three-tier dissimilarity and Theil decomposition in the free-market scenario
fig = Figure(size = (1000, 400))
ax1 = Axis(fig[1, 1], xlabel = "Step", ylabel = "Pairwise dissimilarity", title = "Free market")
for (col, color, lab) in ((:D_low_middle, :purple, "low - middle"), (:D_middle_top, :dodgerblue3, "middle - top"),
                          (:D_low_top, :darkorange2, "low - top"))
    curve!(ax1, summ, "none", col; color, label = lab)
end
axislegend(ax1, position = :rt)
ax2 = Axis(fig[1, 2], xlabel = "Step", ylabel = "Theil index", title = "Free market")
for (col, color, lab) in ((:H_total, :black, "H total"), (:H_between, :firebrick, "H between"),
                          (:H_within_inner, :dodgerblue3, "H inner city"), (:H_within_suburbs, :seagreen, "H suburbs"))
    curve!(ax2, summ, "none", col; color, label = lab)
end
axislegend(ax2, position = :rt)
save(joinpath(FIGURES, "three_tier_theil_$(tag).pdf"), fig)
let f1 = Figure(size = (520, 400))
    ax = Axis(f1[1, 1], xlabel = "Step", ylabel = "Pairwise dissimilarity")
    for (col, color, lab) in ((:D_low_middle, :purple, "low - middle"), (:D_middle_top, :dodgerblue3, "middle - top"),
                              (:D_low_top, :darkorange2, "low - top"))
        curve!(ax, summ, "none", col; color, label = lab)
    end
    axislegend(ax, position = :rt)
    save(joinpath(FIGURES, "dissimilarity_pair_$(tag).pdf"), f1)
end
let f1 = Figure(size = (520, 400))
    ax = Axis(f1[1, 1], xlabel = "Step", ylabel = "Theil index")
    for (col, color, lab) in ((:H_total, :black, "H total"), (:H_between, :firebrick, "H between"),
                              (:H_within_inner, :dodgerblue3, "H inner city"), (:H_within_suburbs, :seagreen, "H suburbs"))
        curve!(ax, summ, "none", col; color, label = lab)
    end
    axislegend(ax, position = :rt)
    save(joinpath(FIGURES, "theil_$(tag).pdf"), f1)
end
println("saved results/compare_$(tag)_*.csv and figures/*_$(tag).pdf")
