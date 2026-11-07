# Dose-response sweep: final inner-city indicators as a function of the public
# housing fraction f, for random and rent-gap targeting (Fig. "threshold" of the paper).
#
#   julia +1.10 -t auto --project scripts/sweep_fraction.jl --tag=paper
#   julia +1.10 -t auto --project scripts/sweep_fraction.jl --tag=once_s2 --mode=once --spillover=2
#   julia +1.10 -t auto --project scripts/sweep_fraction.jl --tag=s0 --spillover=0
#
# Options (all optional):
#   --tag=NAME            label of the output files (results/sweep_NAME*.csv)
#   --fractions=0:0.01:0.15
#   --seeds=paper | 1:20 | 1,2,3
#   --policies=random,rentgap
#   --spillover=2.0       decrease of PR around public units (negative = positive spillover)
#   --mode=every_step|once
#   --exclude_renovated=false
#   --steps=170           dynamic steps
#   --trigger=0.5         rent growth that activates the policy
#   --dims=40             grid side
#   --vacancy=0.075       target vacancy rate
#   --income_threshold=30 income below which a household may use a public unit (and makes its house eligible)
#   --renovation_age_max=15   Inf reproduces the first submission
# First-submission (v1) settings: --mode=every_step --exclude_renovated=false --renovation_age_max=Inf
include(joinpath(@__DIR__, "common.jl"))

args = parse_args()
tag = getarg(args, "tag", "paper")
fractions = parse_list(getarg(args, "fractions", "0:0.01:0.15"))
seeds = parse_seeds(getarg(args, "seeds", "paper"))
policies = Symbol.(split(getarg(args, "policies", "random,rentgap"), ","))
n_dynamics = getarg(args, "steps", 170)

dims = getarg(args, "dims", 40)
base = ModelParams(
    dims = (dims, dims),
    public_housing_spillover = getarg(args, "spillover", 2.0),
    public_housing_spillover_mode = getarg(args, "mode", :once),
    exclude_renovated_from_conversion = getarg(args, "exclude_renovated", true),
    median_rent_growth_trigger = getarg(args, "trigger", 0.5),
    target_vacancy_rate = getarg(args, "vacancy", 0.075),
    public_housing_income_threshold = getarg(args, "income_threshold", 30.0),
    renovation_age_max = getarg(args, "renovation_age_max", 15.0),
)
println("sweep '$tag': $(length(fractions)) fractions x $(length(policies)) policies x $(length(seeds)) seeds, ",
        "$(Threads.nthreads()) threads")
println("spillover=$(base.public_housing_spillover) mode=$(base.public_housing_spillover_mode) ",
        "exclude_renovated=$(base.exclude_renovated_from_conversion) trigger=$(base.median_rent_growth_trigger) ",
        "dims=$(base.dims) vacancy=$(base.target_vacancy_rate) income_threshold=$(base.public_housing_income_threshold) ",
        "renovation_age_max=$(base.renovation_age_max)")

steps = run_grid(base, seeds, fractions, policies; n_dynamics)
CSV.write(joinpath(RESULTS, "sweep_$(tag)_steps.csv"), steps)

final = steps[steps.step .== maximum(steps.step), :]
CSV.write(joinpath(RESULTS, "sweep_$(tag)_final.csv"), final)

summary = combine(groupby(final, [:policy, :ph_fraction]),
    :median_income_inner_city => nanmean => :mean_final_income,
    :median_income_inner_city => sem => :sem_final_income,
    :median_inner_city_rent => nanmean => :mean_final_rent,
    :median_inner_city_rent => sem => :sem_final_rent,
    :n_high_inner => nanmean => :mean_final_n_high_inner,
    :n_low_inner => nanmean => :mean_final_n_low_inner,
    :lcc_gentrification => nanmean => :mean_final_lcc,
    :n_public_housing_inner => nanmean => :mean_ph_inner)
sort!(summary, [:policy, :ph_fraction])
CSV.write(joinpath(RESULTS, "sweep_$(tag)_summary.csv"), summary)
show(stdout, summary, allrows = true); println()
println("saved results/sweep_$(tag)_{steps,final,summary}.csv")
