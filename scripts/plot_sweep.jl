# Plot dose-response curves from one or more sweeps.
#
#   julia +1.10 --project scripts/plot_sweep.jl --tags=paper
#   julia +1.10 --project scripts/plot_sweep.jl --tags=paper,s1,s0,once_s2 --out=spillover_sensitivity
#
# With one tag: final median income and final median rent vs f (random vs rent-gap).
# With several tags: one panel per tag, rent-gap and random curves in each.
include(joinpath(@__DIR__, "common.jl"))
using CairoMakie

args = parse_args()
tags = split(getarg(args, "tags", "paper"), ",")
out = getarg(args, "out", join(tags, "_"))
# descriptive panel titles; --labels=a;b;c overrides
default_labels = Dict("base" => "baseline (spillover -2, once)", "spill0" => "no public-housing spillover",
    "spill4" => "spillover doubled (-4)", "trig025" => "activation at 25% rent growth", "trig075" => "activation at 75% rent growth",
    "vac005" => "vacancy 5%", "vac010" => "vacancy 10%", "inc20" => "eligibility 20k USD", "inc45" => "eligibility 45k USD",
    "grid60" => "60x60 grid, 400 steps", "paper" => "first submission (spillover every step)",
    "s1" => "every step, -1", "s0" => "no spillover", "sneg1" => "every step, +1", "once_s2" => "once, -2", "once_s4" => "once, -4")
labels_arg = getarg(args, "labels", "")
panel_labels = isempty(labels_arg) ? [get(default_labels, t, t) for t in tags] : split(labels_arg, ";")
colors = Dict("random" => :dodgerblue3, "rentgap" => :darkorange2)
labels = Dict("random" => "Random", "rentgap" => "Rent-gap")

function panel!(ax, summary, ycol, yerr)
    for pol in ("random", "rentgap")
        d = sort(summary[summary.policy .== pol, :], :ph_fraction)
        isempty(d) && continue
        errorbars!(ax, d.ph_fraction, d[!, ycol], d[!, yerr], color = colors[pol], whiskerwidth = 6)
        scatterlines!(ax, d.ph_fraction, d[!, ycol], color = colors[pol], label = labels[pol],
                      markersize = 9, linewidth = 2)
    end
end

n = length(tags)
fig = Figure(size = (520 * min(n, 2), 400 * cld(n, 2)))
for (k, tag) in enumerate(tags)
    s = CSV.read(joinpath(RESULTS, "sweep_$(tag)_summary.csv"), DataFrame)
    row, col = cld(k, 2), mod1(k, 2)
    ax = Axis(fig[row, col], xlabel = "Public housing fraction f", ylabel = "Final inner-city median income",
              title = n > 1 ? panel_labels[k] : "", titlesize = 13)
    panel!(ax, s, :mean_final_income, :sem_final_income)
    k == 1 && axislegend(ax, position = :rt)
end
save(joinpath(FIGURES, "final_median_income_$(out).pdf"), fig)
save(joinpath(FIGURES, "final_median_income_$(out).png"), fig, px_per_unit = 2)

if n == 1
    s = CSV.read(joinpath(RESULTS, "sweep_$(tags[1])_summary.csv"), DataFrame)
    fig2 = Figure(size = (520, 400))
    ax = Axis(fig2[1, 1], xlabel = "Public housing fraction f", ylabel = "Final inner-city median rent")
    panel!(ax, s, :mean_final_rent, :sem_final_rent)
    axislegend(ax, position = :rt)
    save(joinpath(FIGURES, "final_median_rent_$(out).pdf"), fig2)
end
println("saved figures/final_median_income_$(out).pdf")
