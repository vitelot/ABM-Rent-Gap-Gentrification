"""
    conversion_candidates(model)

Private housing patches eligible for conversion to public housing: vacant, or
occupied by a household with income below `public_housing_income_threshold`
(and, optionally, never renovated). Row-major order, as in the original code.
Returns a vector of `(gap, pos)` named tuples.
"""
function conversion_candidates(model)
    city = abmproperties(model)
    p = city.params
    out = NamedTuple{(:gap, :pos),Tuple{Float64,Pos}}[]
    for x in 1:p.dims[1], y in 1:p.dims[2]
        pos = (x, y)
        city.patch_type[x, y] == :house && city.management[x, y] == :private || continue
        (p.exclude_renovated_from_conversion && pos in city.renovated_history) && continue
        ids = ids_in_position(pos, model)
        eligible = isempty(ids) || model[first(ids)].income < p.public_housing_income_threshold
        eligible || continue
        pr = city.potential_rent[pos...]
        cr = city.capitalized_rent[pos...]
        gap = (!isnan(pr) && !isnan(cr)) ? pr - cr : 0.0
        push!(out, (gap = gap, pos = pos))
    end
    return out
end

"""
    activate_public_housing!(model)

Convert a fraction `public_housing_fraction` of the housing stock to public
housing, chosen at random (`policy = :random`) or as the highest rent-gap
eligible patches (`policy = :rentgap`). Converted units get the fixed public
rent, their age is frozen (and brought back to `public_housing_renovation_age`
if older), and their maintenance noise is removed.
"""
function activate_public_housing!(model)
    city = abmproperties(model)
    p = city.params
    rng = abmrng(model)
    city.public_housing_active = true
    city.public_housing_activation_step = abmtime(model)

    candidates = conversion_candidates(model)
    order = sortperm([c.gap for c in candidates], rev = true)
    city.candidate_gaps_at_activation = [candidates[k].gap for k in order]
    city.candidate_inner_at_activation = [is_inner_city(candidates[k].pos, city) for k in order]
    n_target = round(Int, city.n_houses * p.public_housing_fraction)
    n = min(n_target, length(candidates))
    n == 0 && return Pos[]

    chosen = if p.policy === :random
        StatsBase.sample(rng, [c.pos for c in candidates], n, replace = false)
    elseif p.policy === :rentgap
        sort!(candidates, by = c -> c.gap, rev = true)
        [c.pos for c in candidates[1:n]]
    else
        error("unknown policy $(p.policy)")
    end

    for pos in chosen
        city.management[pos...] = :public
        city.capitalized_rent[pos...] = city.public_housing_rent
        if city.house_age[pos...] >= p.public_housing_renovation_age
            city.house_age[pos...] = p.public_housing_renovation_age
        end
        city.condition_noise[pos...] = 0.0
        push!(city.public_housing_positions, pos)
    end
    if p.public_housing_spillover_mode === :once
        apply_public_housing_spillover!(city, chosen)
    end
    return chosen
end
