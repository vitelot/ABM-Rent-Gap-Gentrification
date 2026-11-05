"""
    ModelParams

All model parameters with the defaults used in the paper
(Brandoli & Servedio, "Small Interventions, Big Effects").
Construct with keyword arguments, e.g. `ModelParams(policy = :rentgap, public_housing_fraction = 0.06)`.

Notes on the public-housing spillover:
* `public_housing_spillover` is the *decrease* of potential rent applied to the
  Moore neighbours of a public unit (a positive number means a negative spillover;
  a negative number models a positive spillover).
* `public_housing_spillover_mode = :every_step` reproduces the original code: the
  decrease is applied at every step after the policy activates (cumulative, floored
  at `min_potential_rent_factor * base_potential_rent`).
  `:once` applies the decrease only once, at conversion time, which is the
  counterpart of the one-shot positive spillover of a developer renovation.
"""
Base.@kwdef struct ModelParams
    # ---- grid and environment -------------------------------------------------
    dims::NTuple{2,Int} = (40, 40)
    cbd_radius_fraction::Float64 = 0.08          # CBD radius as a fraction of the grid side
    p_amenity_inner::Float64 = 0.17               # probability that an inner-city patch is an amenity
    p_amenity_suburbs::Float64 = 0.20             # same for suburban patches
    amenity_min::Float64 = 0.1                    # amenity level ~ U(amenity_min, amenity_max)
    amenity_max::Float64 = 1.0
    amenity_influence_radius::Int = 2             # Chebyshev radius within which amenities raise potential rent
    amenity_rent_factor::Float64 = 22.0           # alpha in Eq. (potential rent)
    base_potential_rent::Float64 = 3.0            # PR_base
    min_rent_periphery_factor::Float64 = 0.7      # PR_base decays linearly to this fraction at the periphery
    max_house_age::Float64 = 50.0                 # a_max
    age_stochasticity_std::Float64 = 5.0          # sigma_a
    maintenance_noise_std::Float64 = 0.05         # eta_i ~ N(0, this)
    rent_age_decay::Float64 = 0.02                # capitalized rent = PR * (1 - rent_age_decay * age / decay_factor_age_slope + eta)
    decay_factor_age_slope::Float64 = 1.5

    # ---- households ----------------------------------------------------------
    # 2013 ACS household income histogram (thousands of USD), weights in percent
    income_bin_edges::Vector{Float64} = [0, 10, 15, 20, 25, 30, 35, 40, 45, 50, 60, 75, 100, 125, 150, 200, 300]
    income_bin_weights::Vector{Float64} = [8.38, 6.21, 6.24, 6.23, 5.93, 6.0, 5.41, 5.47, 4.85, 9.25, 11.5, 14.1, 9.29, 5.57, 5.65, 5.53]
    min_income::Float64 = 7.0                     # lower bound of the first income bin when sampling
    low_income_percentile::Float64 = 0.6          # agents below this percentile are low income
    middle_income_percentile::Float64 = 0.8       # high-income agents are split into middle (60-80) and top (80-100)
    target_vacancy_rate::Float64 = 0.075
    utility_weights_low::NamedTuple = (financial = 0.35, amenity = 0.25, age = 0.25, center = 0.15, neighborhood = 0.0)
    utility_weights_high::NamedTuple = (financial = 0.25, amenity = 0.21, age = 0.36, center = 0.18, neighborhood = 0.0)
    satisfaction_threshold_low::Float64 = 0.3     # theta_L
    satisfaction_threshold_high::Float64 = 0.6    # theta_H
    n_search_attempts::Int = 10                   # vacant patches sampled by an unhappy agent
    min_age_utility::Float64 = 0.05               # a patch with age utility below this has total utility 0

    # ---- developer -----------------------------------------------------------
    developer_search_sample_size::Int = 30
    developer_investments_per_step::Int = 1
    developer_evaluation_period::Int = 2
    developer_confidence_boost::Float64 = 0.5
    developer_confidence_penalty::Float64 = 0.5
    developer_confidence_threshold::Float64 = 0.4
    developer_confidence_max::Float64 = 3.0
    developer_confidence_reset_value::Float64 = 1.0
    developer_recovery_threshold::Float64 = 0.5
    mean_age_after_renovation::Float64 = 7.0      # renovated age ~ Exp(mean)
    gentrification_spillover_radius::Int = 1
    gentrification_spillover_boost::Float64 = 4.0 # one-shot increase of PR of the neighbours of a renovated patch
    age_step::Float64 = 0.05                      # ageing per dynamic step

    # ---- public housing policy ----------------------------------------------
    policy::Symbol = :none                        # :none, :random, :rentgap
    public_housing_fraction::Float64 = 0.05       # f, fraction of the housing stock converted
    public_housing_rent_percentile::Float64 = 0.30 # public rent = this quantile of the initial CR distribution
    median_rent_growth_trigger::Float64 = 0.5     # policy activates when inner-city median rent grew by this fraction
    public_housing_income_threshold::Float64 = 30.0 # only agents below this income can use (or keep) a public unit
    public_housing_spillover::Float64 = 2.0       # decrease of PR of the neighbours of a public unit
    public_housing_spillover_mode::Symbol = :every_step # :every_step (original code) or :once
    public_housing_spillover_radius::Int = 1
    public_housing_renovation_age::Float64 = 40.0 # converted units older than this are brought back to this age
    exclude_renovated_from_conversion::Bool = false # the original code declares but never fills the renovated set
    min_potential_rent_factor::Float64 = 0.5      # floor of PR under negative spillover, times base_potential_rent
end

"Return a copy of `p` with some fields changed, e.g. `with(p; policy = :rentgap)`."
function with(p::ModelParams; kwargs...)
    fields = Dict{Symbol,Any}(f => getfield(p, f) for f in fieldnames(ModelParams))
    for (k, v) in kwargs
        haskey(fields, k) || error("ModelParams has no field $k")
        fields[k] = v
    end
    return ModelParams(; fields...)
end

"The 15 seeds of the 'successful gentrification' cluster used for all multi-seed figures of the paper."
const PAPER_SEEDS = [928154, 224468, 245633, 234277, 614952, 128866, 228554, 373344,
                     769051, 525478, 233024, 889337, 580, 215646, 9248]
