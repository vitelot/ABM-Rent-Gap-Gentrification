"Mean and median capitalized rent of the private inner-city houses."
function inner_city_rent(city::City)
    rents = Float64[]
    r1, r2, c1, c2 = city.inner_city
    for i in r1:r2, j in c1:c2
        if city.patch_type[i, j] == :house && city.management[i, j] == :private
            v = city.capitalized_rent[i, j]
            isnan(v) || push!(rents, v)
        end
    end
    isempty(rents) && return (mean = NaN, median = NaN, n = 0)
    return (mean = mean(rents), median = median(rents), n = length(rents))
end

"Income tier of a household: :low, :middle or :top."
function income_tier(a::Household, city::City)
    islow(a) && return :low
    return a.income <= city.middle_income_cutoff ? :middle : :top
end

"""
    neighbour_segregation_index(model)

Fraction of neighbour links (Moore radius 1) connecting households of the same group.
"""
function neighbour_segregation_index(model)
    city = abmproperties(model)
    dims = city.params.dims
    grid = fill(:none, dims)
    for a in allagents(model)
        grid[a.pos...] = a.group
    end
    same = 0; total = 0
    for a in allagents(model), np in moore_neighbours(a.pos, 1, dims)
        g = grid[np...]
        g === :none && continue
        total += 1
        g === a.group && (same += 1)
    end
    return total == 0 ? 1.0 : same / total
end

"Mean normalised amenity score of the patches occupied by low- and high-income households."
function amenity_exposure(model)
    city = abmproperties(model)
    range = city.amenity_score_max - city.amenity_score_min
    low = Float64[]; high = Float64[]
    for a in allagents(model)
        push!(islow(a) ? low : high, city.amenity_score[a.pos...])
    end
    f(v) = isempty(v) ? NaN : (mean(v) - city.amenity_score_min) / range
    return (low = f(low), high = f(high))
end

"""
    step_metrics(model, step)

City-level indicators at one step, as a NamedTuple (one row of the metrics table).
"""
function step_metrics(model, step::Int)
    city = abmproperties(model)
    n_low_in = n_high_in = n_low_out = n_high_out = 0
    incomes_in = Float64[]
    for a in allagents(model)
        if is_inner_city(a.pos, city)
            push!(incomes_in, a.income)
            islow(a) ? (n_low_in += 1) : (n_high_in += 1)
        else
            islow(a) ? (n_low_out += 1) : (n_high_out += 1)
        end
    end
    n_house_in = n_house_out = n_public = n_public_in = 0
    for j in 1:city.params.dims[2], i in 1:city.params.dims[1]
        city.patch_type[i, j] == :house || continue
        inner = is_inner_city((i, j), city)
        inner ? (n_house_in += 1) : (n_house_out += 1)
        if city.management[i, j] == :public
            n_public += 1
            inner && (n_public_in += 1)
        end
    end
    rent = inner_city_rent(city)
    amen = amenity_exposure(model)
    return (
        step = step,
        n_low_inner = n_low_in, n_high_inner = n_high_in,
        n_low_suburbs = n_low_out, n_high_suburbs = n_high_out,
        ratio_lh_inner = n_high_in > 0 ? n_low_in / n_high_in : NaN,
        ratio_lh_suburbs = n_high_out > 0 ? n_low_out / n_high_out : NaN,
        density_total_inner = n_house_in > 0 ? (n_low_in + n_high_in) / n_house_in : 0.0,
        density_total_suburbs = n_house_out > 0 ? (n_low_out + n_high_out) / n_house_out : 0.0,
        mean_income_inner_city = isempty(incomes_in) ? NaN : mean(incomes_in),
        median_income_inner_city = isempty(incomes_in) ? NaN : median(incomes_in),
        mean_inner_city_rent = rent.mean,
        median_inner_city_rent = rent.median,
        n_houses_inner_city_rent_calc = rent.n,
        neighbour_segregation_index = neighbour_segregation_index(model),
        amenity_segregation_index_low = amen.low,
        amenity_segregation_index_high = amen.high,
        developer_active = city.developer_active,
        developer_confidence = city.developer_confidence,
        n_renovations = city.renovations_this_step,
        n_renovations_inner = city.renovations_inner_this_step,
        public_housing_active = city.public_housing_active,
        n_public_housing = n_public,
        n_public_housing_inner = n_public_in,
        lcc_gentrification = gentrification_lcc(city),
    )
end

"""
    quadrant_counts(model, step)

Number of low-, middle- and top-income households in each of the 16 quadrants
(10x10 patches on the 40x40 grid). Returns a vector of NamedTuples.
"""
function quadrant_counts(model, step::Int)
    city = abmproperties(model)
    dims = city.params.dims
    qx, qy = div(dims[1], 4), div(dims[2], 4)
    counts = Dict{Pos,Vector{Int}}()
    for a in allagents(model)
        q = (ceil(Int, a.pos[1] / qx), ceil(Int, a.pos[2] / qy))
        v = get!(counts, q, zeros(Int, 3))
        tier = income_tier(a, city)
        v[tier === :low ? 1 : tier === :middle ? 2 : 3] += 1
    end
    rows = NamedTuple[]
    for q in sort(collect(keys(counts)))
        v = counts[q]
        push!(rows, (step = step, qx = q[1], qy = q[2], n_low = v[1], n_medium = v[2], n_high = v[3]))
    end
    return rows
end

# ---------------------------------------------------------------------------
# Post-processing of quadrant tables (one step of one run at a time)
# ---------------------------------------------------------------------------

"Dissimilarity index between the groups in columns `g1` and `g2` of a quadrant table (one step)."
function dissimilarity(q::AbstractDataFrame, g1::Symbol, g2::Symbol)
    t1 = sum(q[!, g1]); t2 = sum(q[!, g2])
    (t1 == 0 || t2 == 0) && return 0.0
    return 0.5 * sum(abs(a / t1 - b / t2) for (a, b) in zip(q[!, g1], q[!, g2]))
end

"Two-group dissimilarity (low vs. high = middle + top)."
dissimilarity_low_high(q::AbstractDataFrame) =
    dissimilarity(DataFrame(low = q.n_low, high = q.n_medium .+ q.n_high), :low, :high)

function entropy3(x, y, z)
    tot = x + y + z
    tot == 0 && return 0.0
    e = 0.0
    for v in (x, y, z)
        v > 0 && (e += v / tot * log(tot / v))
    end
    return e
end

"Theil information index H over the rows (quadrants) of `q`, three income tiers."
function theil(q::AbstractDataFrame)
    L, M, T = sum(q.n_low), sum(q.n_medium), sum(q.n_high)
    N = L + M + T
    N == 0 && return 0.0
    E = entropy3(L, M, T)
    E == 0 && return 0.0
    H = 0.0
    for r in eachrow(q)
        t = r.n_low + r.n_medium + r.n_high
        t > 0 && (H += t * (E - entropy3(r.n_low, r.n_medium, r.n_high)))
    end
    return H / (E * N)
end

"Theil index decomposed into between (inner city vs suburbs) and within components."
function theil_decomposed(q::AbstractDataFrame)
    inner = [(2, 2), (2, 3), (3, 2), (3, 3)]
    isin = [(r.qx, r.qy) in inner for r in eachrow(q)]
    qi, qs = q[isin, :], q[.!isin, :]
    L, M, T = sum(q.n_low), sum(q.n_medium), sum(q.n_high)
    N = L + M + T
    zero = (H_total = 0.0, H_between = 0.0, H_within_inner = 0.0, H_within_suburbs = 0.0)
    N == 0 && return zero
    E = entropy3(L, M, T)
    E == 0 && return zero
    ti = sum(qi.n_low) + sum(qi.n_medium) + sum(qi.n_high)
    ts = sum(qs.n_low) + sum(qs.n_medium) + sum(qs.n_high)
    Ei = entropy3(sum(qi.n_low), sum(qi.n_medium), sum(qi.n_high))
    Es = entropy3(sum(qs.n_low), sum(qs.n_medium), sum(qs.n_high))
    H_between = (E - (ti / N * Ei + ts / N * Es)) / E
    return (H_total = theil(q), H_between = H_between,
            H_within_inner = theil(qi), H_within_suburbs = theil(qs))
end

# ---------------------------------------------------------------------------
# Spatial clusters (percolation picture)
# ---------------------------------------------------------------------------

"Size of the largest Moore-connected component of a set of positions (no graph library needed)."
function largest_component(patches::AbstractSet{Pos})
    isempty(patches) && return 0
    seen = Set{Pos}()
    best = 0
    for start in patches
        start in seen && continue
        size = 0
        stack = [start]
        push!(seen, start)
        while !isempty(stack)
            pos = pop!(stack)
            size += 1
            for di in -1:1, dj in -1:1
                (di == 0 && dj == 0) && continue
                np = (pos[1] + di, pos[2] + dj)
                if np in patches && !(np in seen)
                    push!(seen, np)
                    push!(stack, np)
                end
            end
        end
        best = max(best, size)
    end
    return best
end

"""
Largest connected 'gentrification cluster': patches that were renovated or received a
positive spillover, minus public units and patches that received a negative spillover.
"""
function gentrification_lcc(city::City)
    patches = union(city.renovated_history, city.positive_spillover_history)
    for pos in city.public_housing_positions
        delete!(patches, pos)
    end
    setdiff!(patches, city.negative_spillover_history)
    return largest_component(patches)
end

"Largest connected 'blocking cluster': public units, their negative-spillover neighbours and amenity patches."
function blocking_lcc(city::City)
    patches = Set{Pos}(city.public_housing_positions)
    union!(patches, city.negative_spillover_history)
    for j in 1:city.params.dims[2], i in 1:city.params.dims[1]
        city.patch_type[i, j] == :amenity && push!(patches, (i, j))
    end
    return largest_component(patches)
end
