"""
    Household

A household agent living on a grid patch. `group` is `:low` or `:high`
(split at the 60th income percentile); `income` is in thousands of USD per year.
"""
@agent struct Household(GridAgent{2})
    group::Symbol
    income::Float64
end

islow(a::Household) = a.group === :low
ishigh(a::Household) = a.group === :high
