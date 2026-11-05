"""
    City

Mutable state of the simulated city, stored as the `properties` of the Agents.jl model.
Patch matrices are indexed `[i, j]` with `i` the row (x) and `j` the column (y).

Patch types: `:cbd` (central business district, not habitable), `:amenity`
(park, square, service), `:house`. Management: `:private`, `:public` (public
housing) or `:none` for non-house patches.
"""
mutable struct City
    params::ModelParams
    # environment
    patch_type::Matrix{Symbol}
    management::Matrix{Symbol}
    house_age::Matrix{Float64}
    condition_noise::Matrix{Float64}
    amenity_level::Matrix{Float64}
    amenity_score::Matrix{Float64}       # s_i, the amenity part of the potential rent
    potential_rent::Matrix{Float64}
    capitalized_rent::Matrix{Float64}
    cbd_center::NTuple{2,Int}
    cbd_radius::Float64
    max_dist_from_center::Float64
    inner_city::NTuple{4,Int}            # (r_start, r_end, c_start, c_end)
    amenity_score_min::Float64
    amenity_score_max::Float64
    current_max_observed_age::Float64
    n_houses::Int
    income_cutoff::Float64               # low / high boundary
    middle_income_cutoff::Float64        # middle / top boundary
    phase::Symbol                        # :thermalization or :dynamics
    # developer
    developer_confidence::Float64
    developer_active::Bool
    investments_to_evaluate::Dict{NTuple{2,Int},Int}
    failed_investments::Set{NTuple{2,Int}}
    renovations_this_step::Int
    renovations_inner_this_step::Int
    renovated_history::Set{NTuple{2,Int}}            # every patch ever renovated (bookkeeping)
    positive_spillover_history::Set{NTuple{2,Int}}   # every patch that ever received a positive spillover
    negative_spillover_history::Set{NTuple{2,Int}}   # every patch that ever received a negative spillover
    # policy
    public_housing_active::Bool
    public_housing_activation_step::Int
    public_housing_rent::Float64
    initial_median_inner_city_rent::Float64
    public_housing_positions::Vector{NTuple{2,Int}}
end

const Pos = NTuple{2,Int}

"Positions at Chebyshev distance 1..r from `pos` inside the grid (Moore neighbourhood), centre excluded."
function moore_neighbours(pos::Pos, r::Int, dims::NTuple{2,Int})
    out = Pos[]
    for di in -r:r, dj in -r:r
        (di == 0 && dj == 0) && continue
        i, j = pos[1] + di, pos[2] + dj
        (1 <= i <= dims[1] && 1 <= j <= dims[2]) && push!(out, (i, j))
    end
    return out
end

function inner_city_bounds(dims::NTuple{2,Int})
    r1 = floor(Int, dims[1] / 4) + 1
    r2 = floor(Int, dims[1] * 3 / 4)
    c1 = floor(Int, dims[2] / 4) + 1
    c2 = floor(Int, dims[2] * 3 / 4)
    return (r1, r2, c1, c2)
end

function is_inner_city(pos::Pos, city::City)
    r1, r2, c1, c2 = city.inner_city
    return r1 <= pos[1] <= r2 && c1 <= pos[2] <= c2
end
