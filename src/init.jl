"""
    income_quantile(edges, weights, q)

Income value at cumulative probability `q` of the piecewise-uniform histogram
(linear interpolation inside the bin that contains `q`).
"""
function income_quantile(edges::Vector{Float64}, weights::Vector{Float64}, q::Float64)
    probs = weights ./ sum(weights)
    cum = 0.0
    for (k, pk) in enumerate(probs)
        if cum + pk >= q
            return edges[k] + (q - cum) / pk * (edges[k+1] - edges[k])
        end
        cum += pk
    end
    return edges[end]
end

"Sample one income from the histogram: pick a bin by weight, then uniformly inside it."
function sample_income(rng, edges::Vector{Float64}, probs::Vector{Float64}, min_income::Float64)
    k = wsample(rng, 1:length(probs), probs)
    lo, hi = edges[k], edges[k+1]
    k == 1 && (lo = max(lo, min_income))
    return rand(rng) * (hi - lo) + lo
end

"Condition factor of a house of age `age` with maintenance noise `noise`."
@inline function condition_factor(age, noise, p::ModelParams, floor_value)
    base = max(0.0, 1.0 - (p.rent_age_decay * age) / p.decay_factor_age_slope)
    return clamp(base + noise, floor_value, 1.0)
end

"Random scheduler: all agents in random order (same stream as the original code)."
random_scheduler(model) = shuffle(abmrng(model), collect(allids(model)))

"""
    initialize_model(p::ModelParams; seed)

Build the city and place the households at random. The sequence of random draws
is the same as in the original implementation, so a given seed reproduces the
original simulations.
"""
function initialize_model(p::ModelParams = ModelParams(); seed::Int = 12345)
    rng = MersenneTwister(seed)
    dims = p.dims
    space = GridSpace(dims, periodic = false)

    patch_type = fill(:cbd, dims)
    management = fill(:none, dims)
    house_age = fill(NaN, dims)
    noise = fill(0.0, dims)
    amenity_level = fill(NaN, dims)
    amenity_score = fill(NaN, dims)
    potential_rent = fill(NaN, dims)
    capitalized_rent = fill(NaN, dims)

    cbd_center = dims .÷ 2 .+ 1
    cbd_r = minimum(dims) * p.cbd_radius_fraction
    dx_max = max(cbd_center[1] - 1, dims[1] - cbd_center[1])
    dy_max = max(cbd_center[2] - 1, dims[2] - cbd_center[2])
    max_dist = max(sqrt(dx_max^2 + dy_max^2), 1e-9)
    max_dist_edge = max(max_dist - cbd_r, 1e-9)
    inner = inner_city_bounds(dims)
    amenity_dist = Uniform(p.amenity_min, p.amenity_max)

    # --- patches (column-major loop, as in the original) ---------------------
    n_houses = 0
    for j in 1:dims[2], i in 1:dims[1]
        d = sqrt((i - cbd_center[1])^2 + (j - cbd_center[2])^2)
        if d <= cbd_r
            patch_type[i, j] = :cbd
            continue
        end
        in_inner = inner[1] <= i <= inner[2] && inner[3] <= j <= inner[4]
        p_amenity = in_inner ? p.p_amenity_inner : p.p_amenity_suburbs
        if rand(rng) < p_amenity
            patch_type[i, j] = :amenity
            amenity_level[i, j] = rand(rng, amenity_dist)
        else
            patch_type[i, j] = :house
            management[i, j] = :private
            n_houses += 1
            # mean age decreases linearly with the distance from the CBD edge
            d_edge = max(0.0, d - cbd_r)
            denom = (dx_max + max_dist) / 2 - cbd_r
            f = denom > eps() ? clamp(d_edge / denom, 0.0, 1.0) : 0.0
            mean_age = p.max_house_age * (1.0 - f)
            age_dist = truncated(Normal(mean_age, p.age_stochasticity_std), 0.0, p.max_house_age)
            house_age[i, j] = clamp(rand(rng, age_dist), 0.0, p.max_house_age)
            noise[i, j] = rand(rng, Normal(0, p.maintenance_noise_std))
        end
    end

    # --- rents ---------------------------------------------------------------
    for j in 1:dims[2], i in 1:dims[1]
        patch_type[i, j] == :house || continue
        pos = (i, j)
        s = 0.0
        for np in moore_neighbours(pos, p.amenity_influence_radius, dims)
            if patch_type[np...] == :amenity && !isnan(amenity_level[np...])
                dist = max(abs(pos[1] - np[1]), abs(pos[2] - np[2]))
                s += amenity_level[np...] / (dist * 1.5)
            end
        end
        amenity_score[i, j] = s
        d = sqrt((i - cbd_center[1])^2 + (j - cbd_center[2])^2)
        d_edge = max(0.0, d - cbd_r)
        f = clamp(d_edge / max_dist_edge, 0.0, 1.0)
        base = p.base_potential_rent * (1.0 - f * (1.0 - p.min_rent_periphery_factor))
        pr = base + p.amenity_rent_factor * s
        potential_rent[i, j] = pr
        capitalized_rent[i, j] = pr * condition_factor(house_age[i, j], noise[i, j], p, 0.08)
    end

    scores = filter(!isnan, vec(amenity_score))
    s_min = isempty(scores) ? 0.0 : minimum(scores)
    s_max = isempty(scores) ? 0.0 : maximum(scores)

    all_cr = [capitalized_rent[i, j] for j in 1:dims[2], i in 1:dims[1] if patch_type[i, j] == :house]
    inner_cr = [capitalized_rent[i, j] for j in 1:dims[2], i in 1:dims[1]
                if patch_type[i, j] == :house && inner[1] <= i <= inner[2] && inner[3] <= j <= inner[4]]
    ph_rent = length(all_cr) > 1 ? quantile(all_cr, p.public_housing_rent_percentile) :
              (isempty(all_cr) ? 0.0 : all_cr[1])
    inner_median = isempty(inner_cr) ? 0.0 : median(inner_cr)

    income_cutoff = income_quantile(p.income_bin_edges, p.income_bin_weights, p.low_income_percentile)
    middle_cutoff = income_quantile(p.income_bin_edges, p.income_bin_weights, p.middle_income_percentile)

    city = City(p, patch_type, management, house_age, noise, amenity_level, amenity_score,
                potential_rent, capitalized_rent, cbd_center, cbd_r, max_dist, inner,
                s_min, s_max, p.max_house_age, n_houses, income_cutoff, middle_cutoff,
                :thermalization,
                1.0, true, Dict{Pos,Int}(), Set{Pos}(), 0, 0, Set{Pos}(), Set{Pos}(), Set{Pos}(),
                false, -1, ph_rent, inner_median, Pos[], Float64[], Bool[])

    model = StandardABM(Household, space; agent_step!, model_step!, properties = city,
                        rng, scheduler = random_scheduler, warn = false)

    # --- households ----------------------------------------------------------
    n_agents = round(Int, n_houses * (1.0 - p.target_vacancy_rate))
    positions = [(i, j) for j in 1:dims[2] for i in 1:dims[1] if patch_type[i, j] == :house]
    shuffle!(rng, positions)
    probs = p.income_bin_weights ./ sum(p.income_bin_weights)
    for _ in 1:min(n_agents, length(positions))
        pos = pop!(positions)
        income = sample_income(rng, p.income_bin_edges, probs, p.min_income)
        group = income < income_cutoff ? :low : :high
        add_agent!(pos, Household, model, group, income)
    end
    return model
end
