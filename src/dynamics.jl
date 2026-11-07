"""
    agent_step!(a, model)

Schelling-like relocation: if the utility of the current patch is below the
group-specific happiness threshold, sample `n_search_attempts` vacant patches
and move to the best one if it improves the utility. Once the public-housing
policy is active, only households below `public_housing_income_threshold`
can enter public units, and they look at those first.
"""
function agent_step!(a::Household, model)
    city = abmproperties(model)
    p = city.params
    u = total_utility(a, a.pos, model)
    threshold = islow(a) ? p.satisfaction_threshold_low : p.satisfaction_threshold_high
    u < threshold || return
    rng = abmrng(model)

    local candidates::Vector{Pos}
    if !city.public_housing_active
        pool = vacant_positions(model, :any)
        isempty(pool) && return
        candidates = shuffled_subset(rng, pool, min(length(pool), p.n_search_attempts))
    else
        private = vacant_positions(model, :private)
        public = vacant_positions(model, :public)
        if islow(a) && a.income < p.public_housing_income_threshold
            k = min(length(public), p.n_search_attempts)
            candidates = k > 0 ? shuffled_subset(rng, public, k) : Pos[]
            remaining = p.n_search_attempts - length(candidates)
            if remaining > 0 && !isempty(private)
                append!(candidates, shuffled_subset(rng, private, min(length(private), remaining)))
            end
        else
            candidates = shuffled_subset(rng, private, min(length(private), p.n_search_attempts))
        end
        isempty(candidates) && return
    end

    best_u = -1.0
    best_pos = nothing
    for pos in candidates
        u_new = total_utility(a, pos, model)
        if u_new > best_u
            best_u = u_new
            best_pos = pos
        end
    end
    if best_pos !== nothing && best_u > u
        move_agent!(a, best_pos, model)
    end
    return
end

"""
    model_step!(model)

One step of the gentrification dynamics (nothing happens during thermalization):
1. public-housing policy trigger (if a policy is set),
2. developer feedback on past investments,
3. developer investment in the highest rent-gap vacant patches,
4. positive spillover on the neighbours of renovated patches,
5. negative spillover from public units (every step, in the original formulation),
6. ageing and update of the capitalized rents.
"""
function model_step!(model)
    city = abmproperties(model)
    city.phase === :dynamics || return
    p = city.params
    rng = abmrng(model)
    t = abmtime(model)
    dims = p.dims

    # 1. policy trigger -------------------------------------------------------
    if p.policy !== :none && !city.public_housing_active
        m = inner_city_rent(city).median
        growth = city.initial_median_inner_city_rent > 0 ?
                 (m - city.initial_median_inner_city_rent) / city.initial_median_inner_city_rent : 0.0
        if growth >= p.median_rent_growth_trigger
            activate_public_housing!(model)
        end
    end

    # 2. developer feedback ----------------------------------------------------
    evaluated = Pos[]
    for (pos, t_ren) in pairs(city.investments_to_evaluate)
        if !isempty(ids_in_position(pos, model))
            city.developer_confidence += p.developer_confidence_boost
            push!(evaluated, pos)
        elseif t - t_ren >= p.developer_evaluation_period
            city.developer_confidence -= p.developer_confidence_penalty
            push!(city.failed_investments, pos)
            push!(evaluated, pos)
        end
    end
    foreach(pos -> delete!(city.investments_to_evaluate, pos), evaluated)
    city.developer_confidence = clamp(city.developer_confidence, 0.0, p.developer_confidence_max)

    if !city.developer_active
        nf = length(city.failed_investments)
        if nf > 0
            occupied = count(pos -> !isempty(ids_in_position(pos, model)), city.failed_investments)
            if occupied / nf >= p.developer_recovery_threshold
                city.developer_active = true
                city.developer_confidence = p.developer_confidence_reset_value
                empty!(city.failed_investments)
            end
        end
    end
    if city.developer_active && city.developer_confidence < p.developer_confidence_threshold
        city.developer_active = false
    end

    # 3. developer investment ---------------------------------------------------
    pool = vacant_positions(model, city.public_housing_active ? :private : :any)
    n_renovate = 0
    gaps = NamedTuple{(:gap, :pos),Tuple{Float64,Pos}}[]
    if city.developer_active && !isempty(pool)
        k = min(length(pool), p.developer_search_sample_size)
        sampled = StatsBase.sample(rng, pool, k, replace = false)
        for pos in sampled
            pr = city.potential_rent[pos...]
            cr = city.capitalized_rent[pos...]
            if !isnan(pr) && !isnan(cr) && pr > cr
                push!(gaps, (gap = pr - cr, pos = pos))
            end
        end
        if !isempty(gaps)
            sort!(gaps, by = g -> g.gap, rev = true)
            n_renovate = round(Int, p.developer_investments_per_step * city.developer_confidence)
            n_renovate = min(n_renovate, length(gaps))
        end
    end

    renovated = Pos[]
    n_inner = 0
    for k in 1:n_renovate
        pos = gaps[k].pos
        is_inner_city(pos, city) && (n_inner += 1)
        city.house_age[pos...] = clamp(rand(rng, Exponential(p.mean_age_after_renovation)), 0.0, p.renovation_age_max)
        city.investments_to_evaluate[pos] = t
        push!(renovated, pos)
        push!(city.renovated_history, pos)
    end
    city.renovations_this_step = n_renovate
    city.renovations_inner_this_step = n_inner

    # 4. positive spillover ------------------------------------------------------
    if !isempty(renovated)
        to_boost = Set{Pos}()
        for pos in renovated, np in moore_neighbours(pos, p.gentrification_spillover_radius, dims)
            city.patch_type[np...] == :house || continue
            (city.public_housing_active && city.management[np...] != :private) && continue
            np in renovated && continue
            push!(to_boost, np)
        end
        for np in to_boost
            city.potential_rent[np...] += p.gentrification_spillover_boost
            push!(city.positive_spillover_history, np)
        end
    end

    # 5. negative spillover from public housing (original: every step) ---------
    if city.public_housing_active && p.public_housing_spillover_mode === :every_step
        apply_public_housing_spillover!(city, city.public_housing_positions)
    end

    # 6. ageing and rents ---------------------------------------------------------
    for j in 1:dims[2], i in 1:dims[1]
        city.patch_type[i, j] == :house || continue
        if city.public_housing_active && city.management[i, j] == :public
            city.capitalized_rent[i, j] = city.public_housing_rent   # frozen age and rent
        else
            age = city.house_age[i, j]
            isnan(age) && continue
            pr = city.potential_rent[i, j]
            city.capitalized_rent[i, j] = clamp(pr * condition_factor(age, city.condition_noise[i, j], p, 0.1), 0.0, pr)
            city.house_age[i, j] = age + p.age_step
        end
    end
    ages = filter(!isnan, vec(city.house_age))
    city.current_max_observed_age = max(isempty(ages) ? 0.0 : maximum(ages), p.max_house_age)
    return
end

"""
Decrease the potential rent of the private neighbours of the public units in
`sources` by `public_housing_spillover`, with a floor at
`min_potential_rent_factor * base_potential_rent`. Each neighbour is hit once
per call even if it touches several public units.
"""
function apply_public_housing_spillover!(city::City, sources::Vector{Pos})
    p = city.params
    targets = Set{Pos}()
    for pos in sources, np in moore_neighbours(pos, p.public_housing_spillover_radius, p.dims)
        city.patch_type[np...] == :house || continue
        city.management[np...] == :private || continue
        (p.exclude_renovated_from_conversion && np in city.renovated_history) && continue
        push!(targets, np)
    end
    floor_pr = p.base_potential_rent * p.min_potential_rent_factor
    for np in targets
        city.potential_rent[np...] = max(city.potential_rent[np...] - p.public_housing_spillover, floor_pr)
        push!(city.negative_spillover_history, np)
    end
    return length(targets)
end
