"""
    RentGapCity

Agent-based rent-gap model of gentrification with public-housing interventions
(Brandoli & Servedio). Load with

    include("src/RentGapCity.jl"); using .RentGapCity

Main entry points: `ModelParams`, `run_scenario`, `run_multi_seed`.
"""
module RentGapCity

using Agents
using Random
using Distributions
using StatsBase
using Statistics
using DataFrames

export ModelParams, with, PAPER_SEEDS, Household, City,
       initialize_model, run_scenario, run_multi_seed,
       step_metrics, quadrant_counts, segregation_table, summarize_by_step, sem, nanmean,
       dissimilarity, dissimilarity_low_high, theil, theil_decomposed,
       gentrification_lcc, blocking_lcc, largest_component,
       inner_city_rent, is_inner_city, moore_neighbours, total_utility

include("parameters.jl")
include("agents.jl")
include("city.jl")
include("utility.jl")
include("dynamics.jl")
include("policy.jl")
include("init.jl")
include("metrics.jl")
include("run.jl")

end # module
