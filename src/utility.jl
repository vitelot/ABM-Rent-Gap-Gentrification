"""
Utility of a household for a housing patch: weighted sum of financial, amenity,
age and centrality components (plus an optional neighbourhood-homophily term,
weight 0 in the paper). Unaffordable patches and patches with a very low age
utility have utility 0.
"""
function total_utility(a::Household, pos::Pos, model)
    city = abmproperties(model)
    p = city.params
    rent = city.capitalized_rent[pos...]
    isnan(rent) && return 0.0

    # financial
    u_fin = if a.income <= 0.0
        rent > 0.0 ? 0.0 : 1.0
    elseif rent <= 0.0
        1.0
    elseif rent >= a.income
        0.0
    else
        clamp((a.income - rent) / a.income, 0.0, 1.0)
    end
    (u_fin == 0.0 && rent > 0.0) && return 0.0

    # amenities (min-max normalised score)
    s = city.amenity_score[pos...]
    range = city.amenity_score_max - city.amenity_score_min
    u_amenity = if abs(range) < 1e-9
        (abs(city.amenity_score_min) < 1e-9 && abs(s) < 1e-9) ? 0.0 : 0.5
    else
        clamp((s - city.amenity_score_min) / range, 0.0, 1.0)
    end

    # age
    age = city.house_age[pos...]
    u_age = 0.0
    if !isnan(age)
        if city.current_max_observed_age > 0.0
            u_age = clamp((city.current_max_observed_age - age) / city.current_max_observed_age, 0.0, 1.0)
        elseif age == 0.0
            u_age = 1.0
        end
    end
    u_age < p.min_age_utility && return 0.0

    # distance from the CBD
    d = sqrt((pos[1] - city.cbd_center[1])^2 + (pos[2] - city.cbd_center[2])^2)
    u_center = clamp(1.0 - d / city.max_dist_from_center, 0.0, 1.0)

    w = islow(a) ? p.utility_weights_low : p.utility_weights_high
    u_neigh = w.neighborhood == 0.0 ? 0.0 : neighbourhood_utility(a, pos, model)

    u = w.financial * u_fin + w.amenity * u_amenity + w.age * u_age + w.center * u_center +
        w.neighborhood * u_neigh
    return clamp(u, 0.0, 1.0)
end

"Fraction of same-group households among the Moore neighbours of `pos`."
function neighbourhood_utility(a::Household, pos::Pos, model)
    same = 0; n = 0
    for id in nearby_ids(pos, model, 1)
        n += 1
        model[id].group === a.group && (same += 1)
    end
    return n == 0 ? 0.0 : same / n
end

"""
    vacant_positions(model, kind)

Vacant housing patches in row-major order (same order as the original code,
which matters for the random sampling). `kind` is `:any`, `:private` or `:public`.
"""
function vacant_positions(model, kind::Symbol = :any)
    city = abmproperties(model)
    out = Pos[]
    dims = size(city.patch_type)
    for r in 1:dims[1], c in 1:dims[2]
        city.patch_type[r, c] == :house || continue
        kind == :any || city.management[r, c] == kind || continue
        isempty(ids_in_position((r, c), model)) && push!(out, (r, c))
    end
    return out
end

"Take `k` elements of `pool` by shuffling an index vector (identical to the original sampler)."
function shuffled_subset(rng, pool::AbstractVector, k::Int)
    k == 0 && return similar(pool, 0)
    idx = collect(1:length(pool))
    shuffle!(rng, idx)
    return pool[view(idx, 1:k)]
end
