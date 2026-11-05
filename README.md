# ABM-Rent-Gap-Gentrification

Agent-based rent-gap model of gentrification with public-housing interventions,
in Julia with [Agents.jl](https://juliadynamics.github.io/Agents.jl/stable/).
Companion code of F. Brandoli and V. D. P. Servedio, *Small Interventions, Big
Effects: Targeted Public Housing Against Gentrification* (submitted to *Cities*).
The model was developed for Flavio Brandoli's MSc thesis (Physics of Complex
Systems, Politecnico di Torino) hosted at the Complexity Science Hub Vienna.

This branch (`vito`) is a rewrite of the original notebook-based code as plain
Julia scripts: same model, same random-number stream (a seed reproduces the
original runs), one unified step function with the policy as a parameter, and a
few extra switches needed for the sensitivity analyses of the revision.

## Model in one paragraph

A 40x40 grid holds a central business district, amenity patches and houses.
Each house has an age (older towards the centre, as in Smith's rent-gap
picture), a potential rent set by nearby amenities and a capitalized rent that
decays with age; the rent gap is their difference. Households (incomes sampled
from the 2013 ACS distribution, split at the 60th percentile into low and high
income) relocate Schelling-style when their utility (affordability, amenities,
housing age, centrality) drops below a threshold. After 15 thermalization
steps a developer starts renovating the vacant houses with the largest rent gap,
raising the potential rent of the neighbours (positive spillover) and adapting
its investment rate to the occupancy of past renovations. When the inner-city
median rent has grown by 50%, a public-housing policy converts a fraction `f`
of the stock, either at random or targeting the highest rent-gap eligible
houses; public units get a fixed low rent, are closed to the developer and
lower the potential rent of their neighbours (negative spillover).

## Layout

```
src/RentGapCity.jl   module entry point (include it, then `using .RentGapCity`)
src/parameters.jl    ModelParams: every parameter with the paper's default
src/agents.jl        Household agent
src/city.jl          City state (patch matrices, developer and policy state)
src/init.jl          initialize_model
src/utility.jl       household utility, vacancy lists, sampling helpers
src/dynamics.jl      agent_step!, model_step! (developer, spillovers, ageing)
src/policy.jl        public-housing conversion (random / rent-gap)
src/metrics.jl       per-step indicators, dissimilarity, Theil, cluster sizes
src/run.jl           run_scenario, run_multi_seed (threaded), summaries
scripts/             command-line drivers (see below)
test/runtests.jl     smoke tests
results/             CSV output of the scripts (per-step tables are git-ignored)
figures/             figures produced by the scripts
```

## Requirements

Julia 1.10 (Agents.jl 6.2 does not precompile on Julia 1.13). With
[juliaup](https://github.com/JuliaLang/juliaup): `juliaup add 1.10`.

```bash
julia +1.10 --project -e 'import Pkg; Pkg.instantiate()'
julia +1.10 --project test/runtests.jl
```

## Running

All scripts take `--key=value` options; defaults reproduce the paper.
Use `-t auto` to run seeds in parallel.

```bash
# dose-response sweep (threshold figure): final indicators vs f, random and rent-gap
julia +1.10 -t auto --project scripts/sweep_fraction.jl --tag=paper
julia +1.10 --project scripts/plot_sweep.jl --tags=paper

# sensitivity to the public-housing spillover
julia +1.10 -t auto --project scripts/sweep_fraction.jl --tag=s0 --spillover=0
julia +1.10 -t auto --project scripts/sweep_fraction.jl --tag=once_s2 --mode=once --spillover=2
julia +1.10 --project scripts/plot_sweep.jl --tags=paper,s0,once_s2 --out=spillover

# time evolution at f = 0.07 (three scenarios) + segregation indices, three-tier D, Theil
julia +1.10 -t auto --project scripts/compare_scenarios.jl --fraction=0.07 --tag=paper

# city maps of one seed and the gentrification cluster before/after the intervention
julia +1.10 --project scripts/city_maps.jl --seed=580 --fraction=0.07
```

Minimal programmatic use:

```julia
include("src/RentGapCity.jl"); using .RentGapCity
p = ModelParams(policy = :rentgap, public_housing_fraction = 0.06)
r = run_scenario(p; seed = 580, n_dynamics = 170)
r.metrics            # DataFrame, one row per step
r.abmproperties(model)   # final City state
```

## Switches added for the revision

* `public_housing_spillover` (default 2.0): decrease of the potential rent of the
  Moore neighbours of a public unit; 0 switches it off, a negative value gives a
  positive spillover.
* `public_housing_spillover_mode`: `:every_step` (original code: the decrease is
  applied at every step after activation, cumulatively, down to a floor of
  `0.5 * base_potential_rent`) or `:once` (applied once at conversion, the
  counterpart of the developer's one-shot positive spillover).
* `exclude_renovated_from_conversion` (default `false`): the original code
  declares the set of renovated houses but never fills it, so renovated houses
  are in practice eligible for conversion and for the negative spillover. Set to
  `true` for the behaviour described in the paper.
* `median_rent_growth_trigger` (default 0.5): activation threshold of the policy
  (intervention timing).

## Reproducibility notes

The random-number calls are issued in the same order as in the original code
(`MersenneTwister(seed)`), so the original seeds give the same cities and the
same trajectories, up to changes in the sampling routines of `Distributions`
and `StatsBase` between package versions. The 15 seeds of the "successful
gentrification" cluster used in the paper are in `PAPER_SEEDS`.

The empirical validation (ACS rent and income series of gentrifying ZIP codes)
is not part of this repository.

## License

MIT, see `LICENSE`.
