# Result panel of the graphical abstract (images/GraphicalAbs_v2.tex in the paper folder).
#   julia +1.9 --project=env-paper scripts/graphical_abstract_panel.jl
include(joinpath(@__DIR__, "common.jl"))
using CairoMakie
s = CSV.read(joinpath(RESULTS, "sweep_base_summary.csv"), DataFrame)
fig = Figure(size = (430, 275), fontsize = 15, backgroundcolor = :white)
ax = Axis(fig[1, 1], xlabel = "Public housing fraction", ylabel = "Final inner-city income",
          xticks = ([0, 0.05, 0.1, 0.15], ["0%", "5%", "10%", "15%"]), yticks = [50, 60, 70],
          xlabelsize = 16, ylabelsize = 16, titlesize = 14)
for (pol, col, lab) in (("random", :dodgerblue3, "Random"), ("rentgap", :red3, "Targeted (rent gap)"))
    d = sort(s[s.policy .== pol, :], :ph_fraction)
    band!(ax, d.ph_fraction, d.mean_final_income .- d.sem_final_income, d.mean_final_income .+ d.sem_final_income, color = (col, 0.2))
    scatterlines!(ax, d.ph_fraction, d.mean_final_income, color = col, linewidth = 3, markersize = 7, label = lab)
end
vlines!(ax, [0.07], color = :black, linestyle = :dash, linewidth = 2)
text!(ax, 0.075, 68.5, text = "7%: eligible high-gap\npool exhausted", align = (:left, :top), fontsize = 13)
text!(ax, 0.12, 60.5, text = "Random", color = :dodgerblue3, fontsize = 16, font = :bold)
text!(ax, 0.02, 56.0, text = "Targeted", color = :red3, fontsize = 16, font = :bold)
ylims!(ax, 51, 71); xlims!(ax, -0.004, 0.155)
save(joinpath(FIGURES, "ga_result_panel.pdf"), fig)
println("ok")
