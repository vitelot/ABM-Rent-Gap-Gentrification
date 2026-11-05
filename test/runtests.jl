# Smoke tests: julia +1.9 --project=env-paper test/runtests.jl (or julia --project test/runtests.jl)
include(joinpath(@__DIR__, "..", "src", "RentGapCity.jl"))
using .RentGapCity
using Test, Statistics, Agents, DataFrames

@testset "initialisation" begin
    m = initialize_model(ModelParams(); seed = 580)
    c = abmproperties(m)
    @test count(==(:house), c.patch_type) == c.n_houses
    @test count(==(:cbd), c.patch_type) == 37
    @test nagents(m) == round(Int, c.n_houses * (1 - 0.075))
    @test 67 < c.income_cutoff < 68           # 60th percentile of the ACS histogram (weights sum to 115.6)
    @test all(a -> (a.income < c.income_cutoff) == RentGapCity.islow(a), allagents(m))
    @test c.public_housing_rent > 0
    # same seed, same city
    m2 = initialize_model(ModelParams(); seed = 580)
    @test isequal(abmproperties(m2).capitalized_rent, c.capitalized_rent)
    @test [a.income for a in allagents(m2)] == [a.income for a in allagents(m)]
end

@testset "dynamics and policy" begin
    r = run_scenario(ModelParams(policy = :rentgap, public_housing_fraction = 0.06); seed = 580, n_dynamics = 60)
    @test nrow(r.metrics) == 76
    @test abmproperties(r.model).public_housing_active
    @test length(abmproperties(r.model).public_housing_positions) == round(Int, 0.06 * abmproperties(r.model).n_houses)
    @test all(abmproperties(r.model).capitalized_rent[pos...] == abmproperties(r.model).public_housing_rent
              for pos in abmproperties(r.model).public_housing_positions)
    # public units only host low-income households below the income threshold
    for pos in abmproperties(r.model).public_housing_positions, id in ids_in_position(pos, r.model)
        @test r.model[id].income < 30.0
    end
    @test all(0 .<= r.quadrants.n_low)
    seg = segregation_table(r.quadrants)
    @test all(0 .<= seg.D_low_high .<= 1)
    @test all(isfinite, seg.H_total) && all(isfinite, seg.H_between)
    # free market: rents grow
    r0 = run_scenario(ModelParams(); seed = 580, n_dynamics = 60, collect_quadrants = false)
    @test r0.metrics.median_inner_city_rent[end] > r0.metrics.median_inner_city_rent[16]
    @test !abmproperties(r0.model).public_housing_active
end

@testset "spillover modes" begin
    p1 = ModelParams(policy = :rentgap, public_housing_fraction = 0.06, public_housing_spillover_mode = :once)
    r1 = run_scenario(p1; seed = 580, n_dynamics = 60, collect_quadrants = false)
    @test abmproperties(r1.model).public_housing_active
    p0 = ModelParams(policy = :rentgap, public_housing_fraction = 0.06, public_housing_spillover = 0.0)
    r0 = run_scenario(p0; seed = 580, n_dynamics = 60, collect_quadrants = false)
    @test all(abmproperties(r0.model).potential_rent[pos...] >= 1.5 for pos in abmproperties(r0.model).negative_spillover_history)
end
println("all tests passed")
