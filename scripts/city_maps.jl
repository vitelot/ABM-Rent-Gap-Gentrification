# City maps of a single run: capitalized rent heat map with the households, before
# the dynamics and at the end, under the three scenarios (Fig. "PH plot"), plus the
# gentrification cluster right before and right after the policy activation
# (Fig. "gentrification cluster").
#
#   julia +1.10 --project scripts/city_maps.jl --seed=580 --fraction=0.07
include(joinpath(@__DIR__, "common.jl"))
using CairoMakie

args = parse_args()
seed = getarg(args, "seed", 580)
f = getarg(args, "fraction", 0.07)
n_dynamics = getarg(args, "steps", 170)
n_therm = 15
base = ModelParams(public_housing_spillover = getarg(args, "spillover", 2.0),
                   public_housing_spillover_mode = getarg(args, "mode", :every_step))

"Heat map of a patch field with agents as dots coloured by group; public units white, amenities green, CBD black."
function city_map!(ax, model; field = :capitalized_rent, range = (0.0, 70.0))
    city = abmproperties(model)
    dims = city.params.dims
    M = getfield(city, field)
    heatmap!(ax, 1:dims[1], 1:dims[2], M; colormap = :viridis, colorrange = range, nan_color = :transparent)
    for j in 1:dims[2], i in 1:dims[1]
        t = city.patch_type[i, j]
        if t == :cbd
            scatter!(ax, [i], [j], marker = :rect, markersize = 11, color = :black)
        elseif t == :amenity
            scatter!(ax, [i], [j], marker = :rect, markersize = 11, color = :forestgreen)
        elseif city.management[i, j] == :public
            scatter!(ax, [i], [j], marker = :rect, markersize = 11, color = :white)
        end
    end
    xs = Float64[]; ys = Float64[]; cs = Symbol[]
    for a in allagents(model)
        push!(xs, a.pos[1]); push!(ys, a.pos[2]); push!(cs, islow(a) ? :dodgerblue : :red)
    end
    scatter!(ax, xs, ys, color = cs, markersize = 5)
    r1, r2, c1, c2 = city.inner_city
    lines!(ax, [r1 - 0.5, r2 + 0.5, r2 + 0.5, r1 - 0.5, r1 - 0.5], [c1 - 0.5, c1 - 0.5, c2 + 0.5, c2 + 0.5, c1 - 0.5],
           color = :black, linestyle = :dash, linewidth = 2)
    hidedecorations!(ax)
    ax.aspect = DataAspect()
end
islow(a) = RentGapCity.islow(a)

runs = Dict{String,Any}()
for (name, pol) in (("none", :none), ("random", :random), ("rentgap", :rentgap))
    p = with(base; policy = pol, public_housing_fraction = f)
    runs[name] = run_scenario(p; seed, n_dynamics, collect_quadrants = false, snapshots = [n_therm])
end

fig = Figure(size = (1400, 950))
Label(fig[0, 1:3], "Seed $seed, f = $f: capitalized rent (colour), low income (blue), high income (red), public units (white)",
      fontsize = 16)
for (k, name) in enumerate(("none", "random", "rentgap"))
    r = runs[name]
    ax = Axis(fig[1, k], title = "$name: after thermalization (step $n_therm)")
    city_map!(ax, r.snapshots[n_therm])
    ax = Axis(fig[2, k], title = "$name: final (step $(n_therm + n_dynamics))")
    city_map!(ax, r.model)
end
save(joinpath(FIGURES, "city_maps_seed$(seed)_f$(f).pdf"), fig)
save(joinpath(FIGURES, "city_maps_seed$(seed)_f$(f).png"), fig, px_per_unit = 2)

# ---- gentrification cluster before / after activation (rent-gap targeting) -----
fc = getarg(args, "cluster_fraction", 0.06)
p = with(base; policy = :rentgap, public_housing_fraction = fc)
r = run_scenario(p; seed, n_dynamics, collect_quadrants = false)
t_act = abmproperties(r.model).public_housing_activation_step
if t_act >= 0
    r = run_scenario(p; seed, n_dynamics, collect_quadrants = false, snapshots = [t_act, t_act + 1])
    before, after = r.snapshots[t_act], r.snapshots[t_act + 1]
    function cluster_map!(ax, model)
        city = abmproperties(model)
        dims = city.params.dims
        M = fill(NaN, dims)
        patches = union(city.renovated_history, city.positive_spillover_history)
        foreach(pos -> delete!(patches, pos), city.public_housing_positions)
        setdiff!(patches, city.negative_spillover_history)
        for pos in patches; M[pos...] = 1.0; end
        for pos in city.public_housing_positions; M[pos...] = 2.0; end
        for pos in city.negative_spillover_history; (pos in patches) || (M[pos...] = 3.0); end
        heatmap!(ax, 1:dims[1], 1:dims[2], M; colormap = [:darkorange, :white, :steelblue], colorrange = (1, 3),
                 nan_color = :gray90)
        r1, r2, c1, c2 = city.inner_city
        lines!(ax, [r1 - 0.5, r2 + 0.5, r2 + 0.5, r1 - 0.5, r1 - 0.5], [c1 - 0.5, c1 - 0.5, c2 + 0.5, c2 + 0.5, c1 - 0.5],
               color = :black, linestyle = :dash, linewidth = 2)
        hidedecorations!(ax); ax.aspect = DataAspect()
    end
    fig = Figure(size = (1000, 520))
    ax = Axis(fig[1, 1], title = "Before activation (step $t_act): LCC = $(gentrification_lcc(abmproperties(before)))")
    cluster_map!(ax, before)
    ax = Axis(fig[1, 2], title = "After activation (step $(t_act + 1)): LCC = $(gentrification_lcc(abmproperties(after)))")
    cluster_map!(ax, after)
    Label(fig[0, 1:2], "Gentrification cluster (orange), public units (white), negative spillover (blue); seed $seed, rent-gap f = $fc",
          fontsize = 14)
    save(joinpath(FIGURES, "gentrification_cluster_seed$(seed)_f$(fc).pdf"), fig)
    println("activation step $t_act, LCC before/after: $(gentrification_lcc(abmproperties(before))) / $(gentrification_lcc(abmproperties(after)))")
else
    println("policy never activated for seed $seed")
end
println("saved figures/city_maps_seed$(seed)_f$(f).pdf")
