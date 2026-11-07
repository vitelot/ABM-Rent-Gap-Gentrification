# Rent-gap profile of the houses eligible for conversion at the moment the policy
# activates (one run per seed; the profile does not depend on f because the
# trajectory before activation does not). Writes results/candidate_profile_<tag>.csv
# with columns seed, rank, gap, inner, and prints the number of eligible houses
# and the size of the inner-city, high-gap set.
#
#   julia +1.9 -t auto --project=env-paper scripts/candidate_profile.jl --tag=base
include(joinpath(@__DIR__, "common.jl"))

args = parse_args()
tag = getarg(args, "tag", "base")
seeds = parse_seeds(getarg(args, "seeds", "paper"))
dims = getarg(args, "dims", 40)
p = ModelParams(policy = :rentgap, public_housing_fraction = 0.06, dims = (dims, dims),
                public_housing_spillover = getarg(args, "spillover", 2.0),
                median_rent_growth_trigger = getarg(args, "trigger", 0.5),
                target_vacancy_rate = getarg(args, "vacancy", 0.075),
                public_housing_income_threshold = getarg(args, "income_threshold", 30.0))

rows = NamedTuple[]
Threads.@threads for k in eachindex(seeds)
    r = run_scenario(p; seed = seeds[k], n_dynamics = getarg(args, "steps", 170), collect_quadrants = false)
    c = abmproperties(r.model)
    for (rank, (g, inner)) in enumerate(zip(c.candidate_gaps_at_activation, c.candidate_inner_at_activation))
        push!(rows, (seed = seeds[k], rank = rank, gap = g, inner = inner, n_houses = c.n_houses,
                     activation_step = c.public_housing_activation_step))
    end
end
df = DataFrame(rows)
sort!(df, [:seed, :rank])
CSV.write(joinpath(RESULTS, "candidate_profile_$(tag).csv"), df)

# summary per seed: eligible houses, share in the inner city among the top 6%, gap at ranks 0.02N..0.15N
println("seed   N_houses t_act  n_eligible  inner@top6%  gap@0.02N  gap@0.06N  gap@0.10N  gap@0.15N")
for g in groupby(df, :seed)
    N = first(g.n_houses)
    gap_at(f) = (k = round(Int, f * N); k <= nrow(g) ? g.gap[k] : NaN)
    k6 = round(Int, 0.06 * N)
    inner6 = mean(g.inner[1:min(k6, nrow(g))])
    @printf("%-7d %5d %5d %9d %10.2f %10.1f %10.1f %10.1f %10.1f\n", first(g.seed), N, first(g.activation_step),
            nrow(g), inner6, gap_at(0.02), gap_at(0.06), gap_at(0.10), gap_at(0.15))
end
println("saved results/candidate_profile_$(tag).csv")
