module TDThreshold

using LinearAlgebra
using Random
using Printf
using Base.Threads

mutable struct SplitMix64RNG
    state::UInt64
end

@inline function splitmix64_next!(rng::SplitMix64RNG)::UInt64
    rng.state += 0x9E3779B97F4A7C15
    z = rng.state
    z = (z ⊻ (z >> 30)) * 0xBF58476D1CE4E5B9
    z = (z ⊻ (z >> 27)) * 0x94D049BB133111EB
    return z ⊻ (z >> 31)
end

@inline rand_unit(rng::SplitMix64RNG) = Float64(splitmix64_next!(rng) >> 11) * 0x1.0p-53
@inline rand_unit(rng::AbstractRNG) = rand(rng)

# Deterministic per-run seed without relying on session hash.
@inline function stable_seed(alpha::Float64, run_idx::Int, salt::UInt64=UInt64(0))
    a = reinterpret(UInt64, alpha)
    b = UInt64(run_idx)
    z = (a * 0x9E3779B97F4A7C15) ⊻ (b * 0xD2B74407B1CE6E93) ⊻ salt ⊻ 0x94D049BB133111EB
    return mod(z, UInt64(0x7fffffff)) + UInt64(1)
end

###############################
# Linear FA: v(s) = w' * phi(s)
###############################
mutable struct LinearValueFunc
    w::Vector{Float64}
end

LinearValueFunc(d::Integer) = LinearValueFunc(zeros(d))

@inline value(vf::LinearValueFunc, phi::AbstractVector{<:Real})::Float64 = dot(vf.w, phi)

#########################
# Generic finite-state TD environments
#########################

struct FiniteTDEnv
    env_id::String
    display_name::String
    gamma::Float64
    n_states::Int
    d::Int
    P::Matrix{Float64}
    D::Vector{Float64}
    Phi::Matrix{Float64}
    theta_star::Vector{Float64}
    V_star::Vector{Float64}
    r::Matrix{Float64}
    start_state::Int
    metadata::Dict{String,String}
end

function canonical_env_id(name::AbstractString)
    env = lowercase(strip(name))
    env = replace(env, '-' => "", '_' => "", ' ' => "")
    aliases = Dict(
        "toyexample" => "toyexample",
        "e1" => "E1",
        "e2" => "E2",
        "e3" => "E3",
        "e4" => "E4",
        "e5" => "E5",
        "e6" => "E6",
        "e7" => "E7",
        "e8" => "E8",
        "e9" => "E9",
        "e10" => "E10",
    )
    return get(aliases, env, name)
end

available_environment_ids() = ["toyexample", "E1", "E2", "E3", "E4", "E5", "E6", "E7", "E8", "E9", "E10"]

function default_environment_params(env_id::AbstractString)
    env = canonical_env_id(env_id)
    if env == "toyexample"
        return Dict("gamma" => "0.99", "seed" => "114514", "scale_factor" => "1.0")
    elseif env == "E1"
        return Dict("gamma" => "0.99", "eps1" => "1e-3", "eps2" => "1e-2", "reward_mode" => "zero", "rho" => "1.0")
    elseif env == "E2"
        return Dict("gamma" => "0.99", "eps1" => "1e-3", "eps2" => "1e-2", "reward_mode" => "zero", "rho" => "1.0")
    elseif env == "E3"
        # new E3 <- old E4
        return Dict("gamma" => "0.99", "eps1" => "1e-3", "eps2" => "1e-2", "reward_mode" => "zero", "rho" => "1.0")
    elseif env == "E4"
        # new E4 <- old E5
        return Dict("gamma" => "0.99", "m" => "20", "eps1" => "1e-2", "reward_mode" => "zero", "rho" => "1.0")
    elseif env == "E5"
        # new E5 <- old E6
        return Dict("gamma" => "0.99", "m" => "20", "eps1" => "1e-2", "reward_mode" => "zero", "rho" => "1.0")
    elseif env == "E6"
        # new E6 <- old E8
        return Dict("gamma" => "0.99", "m" => "32", "eps1" => "1e-2", "reward_mode" => "zero", "rho" => "1.0")
    elseif env == "E7"
        # new E7 <- old E9
        return Dict("gamma" => "0.99", "m" => "64", "eps1" => "1e-2", "alpha_max" => string(pi / 2), "reward_mode" => "zero", "rho" => "1.0")
    elseif env == "E8"
        # new E8 <- old E10
        return Dict("gamma" => "0.99", "eps1" => "1e-2", "eps2" => "1e-2", "reward_mode" => "zero", "rho" => "1.0")
    elseif env == "E9"
        # new E9 <- old E11
        return Dict("gamma" => "0.99", "m" => "50", "eps2" => "1e-2", "reward_mode" => "zero", "rho" => "1.0")
    elseif env == "E10"
        # new E10 <- old E12
        return Dict("gamma" => "0.99", "k" => "10", "eps1" => "1e-3", "eps2" => "1e-2", "reward_mode" => "cluster-opposite", "rho" => "1.0")
    end
    error("Unknown environment id: $env_id")
end

function _relabel_environment(env::FiniteTDEnv, new_id::AbstractString, new_name::AbstractString)
    return FiniteTDEnv(
        String(new_id),
        String(new_name),
        env.gamma,
        env.n_states,
        env.d,
        env.P,
        env.D,
        env.Phi,
        env.theta_star,
        env.V_star,
        env.r,
        env.start_state,
        env.metadata,
    )
end

function build_environment(env_id::AbstractString; params::Dict{String,String}=Dict{String,String}())
    env = canonical_env_id(env_id)
    merged = _merge_params(default_environment_params(env), params)
    if env == "toyexample"
        return _build_toyexample(merged)
    elseif env == "E1"
        return _build_e1(merged)
    elseif env == "E2"
        return _build_e2(merged)
    elseif env == "E3"
        return _relabel_environment(_build_e4(merged), "E3", "E3 metastable trap")
    elseif env == "E4"
        return _relabel_environment(_build_e5(merged), "E4", "E4 cycle transport")
    elseif env == "E5"
        return _relabel_environment(_build_e6(merged), "E5", "E5 conveyor with reset")
    elseif env == "E6"
        return _relabel_environment(_build_e8(merged), "E6", "E6 rotating-arc ring")
    elseif env == "E7"
        return _relabel_environment(_build_e9(merged), "E7", "E7 open excursion arc")
    elseif env == "E8"
        return _relabel_environment(_build_e10(merged), "E8", "E8 bow-tie cycle")
    elseif env == "E9"
        return _relabel_environment(_build_e11(merged), "E9", "E9 diffusive corridor")
    elseif env == "E10"
        return _relabel_environment(_build_e12(merged), "E10", "E10 two-cluster forcing")
    end
    error("Unknown environment id: $env_id")
end

function default_environment_sweeps(env_id::AbstractString)
    env = canonical_env_id(env_id)
    if env == "toyexample"
        vals = [@sprintf("%.12g", 2.0^k) for k in -10:2:10]
        return Dict("scale_factor" => vals)
    end
    return Dict{String,Vector{String}}()
end

function _merge_params(defaults::Dict{String,String}, overrides::Dict{String,String})
    merged = copy(defaults)
    for (k, v) in overrides
        merged[k] = v
    end
    return merged
end

_string_param(params::Dict{String,String}, key::AbstractString, default::AbstractString) = get(params, String(key), String(default))

function _float_param(params::Dict{String,String}, key::AbstractString, default::Real)
    return parse(Float64, get(params, String(key), @sprintf("%.16g", float(default))))
end

function _int_param(params::Dict{String,String}, key::AbstractString, default::Integer)
    return parse(Int, get(params, String(key), string(default)))
end

function _format_metadata(params::Dict{String,String}, keys::Vector{String})
    out = Dict{String,String}()
    for key in keys
        if haskey(params, key)
            out[key] = params[key]
        end
    end
    return out
end

function _stationary_distribution(P::Matrix{Float64})
    vals, vecs = eigen(transpose(P))
    idx = argmin(abs.(vals .- 1.0))
    stat = abs.(real(vecs[:, idx]))
    total = sum(stat)
    if !(total > 0)
        return fill(1.0 / size(P, 1), size(P, 1))
    end
    return vec(stat ./ total)
end

function _safe_theta_star(A::Matrix{Float64}, b::Vector{Float64})
    try
        return A \ b
    catch
        return pinv(A) * b
    end
end

function _state_reward_matrix(r::Vector{Float64})
    return repeat(reshape(r, :, 1), 1, length(r))
end

function _alternate_transition_matrix(eps1::Float64)
    return [eps1 1.0 - eps1; 1.0 - eps1 eps1]
end

function _sticky_transition_matrix(eps1::Float64)
    return [1.0 - eps1 eps1; eps1 1.0 - eps1]
end

function _ring_transition_matrix(m::Int, eps1::Float64)
    P = zeros(Float64, m, m)
    @inbounds for i in 1:m
        P[i, i] = eps1
        P[i, (i % m) + 1] = 1.0 - eps1
    end
    return P
end

function _conveyor_transition_matrix(m::Int, eps1::Float64)
    n_states = m + 1
    P = zeros(Float64, n_states, n_states)
    P[1, 1] = 1.0 - eps1
    P[1, 2] = eps1
    @inbounds for i in 2:m
        P[i, i + 1] = 1.0
    end
    P[n_states, 1] = 1.0
    return P
end

function _reflecting_corridor_transition_matrix(m::Int)
    n_states = m + 1
    P = zeros(Float64, n_states, n_states)
    P[1, 1] = 0.75
    P[1, 2] = 0.25
    @inbounds for i in 2:m
        P[i, i - 1] = 0.25
        P[i, i] = 0.5
        P[i, i + 1] = 0.25
    end
    P[n_states, n_states] = 0.75
    P[n_states, n_states - 1] = 0.25
    return P
end

function _normalize_rows!(P::Matrix{Float64})
    @inbounds for i in 1:size(P, 1)
        s = sum(@view P[i, :])
        if s <= 0
            error("Transition row $i has non-positive mass")
        end
        P[i, :] ./= s
    end
    return P
end

function _finalize_environment(env_id::AbstractString, display_name::AbstractString, gamma::Float64,
                               P::Matrix{Float64}, Phi::Matrix{Float64}, r::Matrix{Float64};
                               start_state::Int=1, metadata::Dict{String,String}=Dict{String,String}())
    P = copy(P)
    Phi = copy(Phi)
    r = copy(r)
    _normalize_rows!(P)
    D = _stationary_distribution(P)
    Dm = Diagonal(D)
    r_bar = vec(sum(P .* r, dims=2))
    M = I - gamma * P
    A = transpose(Phi) * (Dm * M * Phi)
    b = transpose(Phi) * (Dm * r_bar)
    theta_star = _safe_theta_star(A, b)
    V_star = Phi * theta_star
    return FiniteTDEnv(String(env_id), String(display_name), gamma, size(P, 1), size(Phi, 2), P, D, Phi, theta_star, V_star, r, start_state, metadata)
end

function _build_toyexample(params::Dict{String,String})
    gamma = _float_param(params, "gamma", 0.99)
    seed = _int_param(params, "seed", 114514)
    scale_factor = _float_param(params, "scale_factor", 1.0)
    n_states = 50
    d = 5

    reward_rng = SplitMix64RNG(UInt64(seed))
    feature_rng = SplitMix64RNG(UInt64(seed))

    P = zeros(Float64, n_states, n_states)
    @inbounds for i in 1:n_states
        P[i, i] = 0.1
        P[i, (i % n_states) + 1] = 0.6
        P[i, ((i - 2 + n_states) % n_states) + 1] = 0.3
    end

    # Fill in row-major visitation order so Julia/C++ consume identical random streams.
    r = zeros(Float64, n_states, n_states)
    @inbounds for i in 1:n_states
        for j in 1:n_states
            r[i, j] = rand_unit(reward_rng)
        end
    end

    Phi = zeros(Float64, n_states, d)
    @inbounds for i in 1:n_states
        for j in 1:d
            Phi[i, j] = 10.0 * rand_unit(feature_rng)
        end
    end
    if scale_factor <= 1.0
        @views Phi[:, 1] .*= scale_factor
    else
        @views Phi[:, :] .*= scale_factor
    end

    metadata = _format_metadata(params, ["gamma", "seed", "scale_factor"])
    return _finalize_environment("toyexample", "ToyExample MDP", gamma, P, Phi, r; start_state=1, metadata=metadata)
end

function _build_e1(params::Dict{String,String})
    gamma = _float_param(params, "gamma", 0.99)
    eps1 = _float_param(params, "eps1", 1e-3)
    eps2 = _float_param(params, "eps2", 1e-2)
    rho = _float_param(params, "rho", 1.0)
    reward_mode = _string_param(params, "reward_mode", "zero")
    P = _alternate_transition_matrix(eps1)
    cphi = sqrt(1.0 + eps2^2)
    Phi = reshape([eps2 / cphi, 1.0 / cphi], 2, 1)
    rewards = reward_mode == "driven" ? [0.0, rho] : [0.0, 0.0]
    metadata = _format_metadata(params, ["gamma", "eps1", "eps2", "rho", "reward_mode"])
    return _finalize_environment("E1", "E1 alternating scalar", gamma, P, Phi, _state_reward_matrix(rewards); start_state=1, metadata=metadata)
end

function _build_e2(params::Dict{String,String})
    gamma = _float_param(params, "gamma", 0.99)
    eps1 = _float_param(params, "eps1", 1e-3)
    eps2 = _float_param(params, "eps2", 1e-2)
    rho = _float_param(params, "rho", 1.0)
    reward_mode = _string_param(params, "reward_mode", "zero")
    P = _sticky_transition_matrix(eps1)
    cphi = sqrt(2.0 + eps2^2)
    Phi = [1.0 0.0; 1.0 eps2] ./ cphi
    rewards = reward_mode == "driven" ? [0.0, rho] : [0.0, 0.0]
    metadata = _format_metadata(params, ["gamma", "eps1", "eps2", "rho", "reward_mode"])
    return _finalize_environment("E2", "E2 sticky two-state block", gamma, P, Phi, _state_reward_matrix(rewards); start_state=1, metadata=metadata)
end

function _build_e3(params::Dict{String,String})
    gamma = _float_param(params, "gamma", 0.99)
    eps1 = _float_param(params, "eps1", 1e-3)
    eps2 = _float_param(params, "eps2", 1e-2)
    rho = _float_param(params, "rho", 1.0)
    reward_mode = _string_param(params, "reward_mode", "zero")
    P = _alternate_transition_matrix(eps1)
    cphi = sqrt(2.0 + eps2^2)
    Phi = [1.0 0.0; 1.0 eps2] ./ cphi
    rewards = reward_mode == "driven" ? [0.0, rho] : [0.0, 0.0]
    metadata = _format_metadata(params, ["gamma", "eps1", "eps2", "rho", "reward_mode"])
    return _finalize_environment("E3", "E3 alternating shear", gamma, P, Phi, _state_reward_matrix(rewards); start_state=1, metadata=metadata)
end

function _build_e4(params::Dict{String,String})
    gamma = _float_param(params, "gamma", 0.99)
    eps1 = _float_param(params, "eps1", 1e-3)
    eps2 = _float_param(params, "eps2", 1e-2)
    rho = _float_param(params, "rho", 1.0)
    reward_mode = _string_param(params, "reward_mode", "zero")
    P = [
        0.0 1.0 0.0;
        1.0 - eps1 0.0 eps1;
        eps1 0.0 1.0 - eps1
    ]
    cphi = sqrt(2.0 + eps2^2)
    Phi = [1.0 0.0; 1.0 eps2; 0.0 0.0] ./ cphi
    rewards = if reward_mode == "weak"
        [0.0, rho, 0.0]
    elseif reward_mode == "signed"
        [0.0, rho, -rho]
    else
        [0.0, 0.0, 0.0]
    end
    metadata = _format_metadata(params, ["gamma", "eps1", "eps2", "rho", "reward_mode"])
    return _finalize_environment("E4", "E4 metastable trap", gamma, P, Phi, _state_reward_matrix(rewards); start_state=1, metadata=metadata)
end

function _build_e5(params::Dict{String,String})
    gamma = _float_param(params, "gamma", 0.99)
    m = _int_param(params, "m", 20)
    eps1 = _float_param(params, "eps1", 1e-2)
    rho = _float_param(params, "rho", 1.0)
    reward_mode = _string_param(params, "reward_mode", "zero")
    P = _ring_transition_matrix(m, eps1)
    Phi = Matrix{Float64}(I, m, m)
    rewards = zeros(Float64, m)
    if reward_mode == "single-site"
        rewards[1] = rho
    elseif reward_mode == "alternating"
        @inbounds for i in 1:m
            rewards[i] = isodd(i) ? -rho : rho
        end
    end
    metadata = _format_metadata(params, ["gamma", "m", "eps1", "rho", "reward_mode"])
    return _finalize_environment("E5", "E5 cycle transport", gamma, P, Phi, _state_reward_matrix(rewards); start_state=1, metadata=metadata)
end

function _build_e6(params::Dict{String,String})
    gamma = _float_param(params, "gamma", 0.99)
    m = _int_param(params, "m", 20)
    eps1 = _float_param(params, "eps1", 1e-2)
    rho = _float_param(params, "rho", 1.0)
    reward_mode = _string_param(params, "reward_mode", "zero")
    P = _conveyor_transition_matrix(m, eps1)
    Phi = zeros(Float64, m + 1, m)
    @inbounds for i in 1:m
        Phi[i + 1, i] = 1.0
    end
    rewards = zeros(Float64, m + 1)
    if reward_mode == "launch"
        rewards[2] = rho
    elseif reward_mode == "excursion"
        rewards[2:end] .= rho
    end
    metadata = _format_metadata(params, ["gamma", "m", "eps1", "rho", "reward_mode"])
    return _finalize_environment("E6", "E6 conveyor with reset", gamma, P, Phi, _state_reward_matrix(rewards); start_state=1, metadata=metadata)
end

function _build_e7(params::Dict{String,String})
    gamma = _float_param(params, "gamma", 0.99)
    eps1 = _float_param(params, "eps1", 1e-3)
    rho = _float_param(params, "rho", 1.0)
    reward_mode = _string_param(params, "reward_mode", "antisymmetric")
    P = _sticky_transition_matrix(eps1)
    Phi = reshape(fill(1.0 / sqrt(2.0), 2), 2, 1)

    rewards = if reward_mode == "antisymmetric"
        [rho, -rho]
    elseif reward_mode == "state1-only"
        [rho, 0.0]
    elseif reward_mode == "state2-only"
        [0.0, rho]
    elseif reward_mode == "same-sign"
        [rho, rho]
    else
        error("Unsupported E7 reward_mode: $reward_mode")
    end

    metadata = _format_metadata(params, ["gamma", "eps1", "rho", "reward_mode"])
    return _finalize_environment("E7", "E7 persistent-sign forcing", gamma, P, Phi, _state_reward_matrix(rewards); start_state=1, metadata=metadata)
end

function _build_e8(params::Dict{String,String})
    gamma = _float_param(params, "gamma", 0.99)
    m = _int_param(params, "m", 32)
    eps1 = _float_param(params, "eps1", 1e-2)
    rho = _float_param(params, "rho", 1.0)
    reward_mode = _string_param(params, "reward_mode", "zero")
    P = _ring_transition_matrix(m, eps1)
    Phi = zeros(Float64, m, 2)
    @inbounds for i in 1:m
        alpha_i = 2.0 * pi * (i - 1) / m
        Phi[i, 1] = cos(alpha_i) / sqrt(m)
        Phi[i, 2] = sin(alpha_i) / sqrt(m)
    end
    rewards = zeros(Float64, m)
    if reward_mode == "single-harmonic"
        @inbounds for i in 1:m
            alpha_i = 2.0 * pi * (i - 1) / m
            rewards[i] = rho * cos(alpha_i)
        end
    elseif reward_mode == "phase-shifted"
        @inbounds for i in 1:m
            alpha_i = 2.0 * pi * (i - 1) / m
            rewards[i] = rho * sin(alpha_i)
        end
    end
    metadata = _format_metadata(params, ["gamma", "m", "eps1", "rho", "reward_mode"])
    return _finalize_environment("E8", "E8 rotating-arc ring", gamma, P, Phi, _state_reward_matrix(rewards); start_state=1, metadata=metadata)
end

function _build_e9(params::Dict{String,String})
    gamma = _float_param(params, "gamma", 0.99)
    m = _int_param(params, "m", 64)
    eps1 = _float_param(params, "eps1", 1e-2)
    alpha_max = _float_param(params, "alpha_max", pi / 2)
    rho = _float_param(params, "rho", 1.0)
    reward_mode = _string_param(params, "reward_mode", "zero")
    n_states = m + 1
    P = zeros(Float64, n_states, n_states)
    P[1, 2] = 1.0
    @inbounds for i in 2:m
        P[i, i + 1] = 1.0 - eps1
        P[i, 1] = eps1
    end
    P[n_states, 1] = 1.0
    Phi = zeros(Float64, n_states, 2)
    @inbounds for i in 1:m
        alpha_i = alpha_max * i / m
        Phi[i + 1, 1] = cos(alpha_i) / sqrt(m)
        Phi[i + 1, 2] = sin(alpha_i) / sqrt(m)
    end
    rewards = zeros(Float64, n_states)
    if reward_mode == "uniform"
        rewards[2:end] .= rho
    elseif reward_mode == "late-excursion"
        start_idx = 1 + cld(m, 2)
        rewards[start_idx + 1:end] .= rho
    end
    metadata = _format_metadata(params, ["gamma", "m", "eps1", "alpha_max", "rho", "reward_mode"])
    return _finalize_environment("E9", "E9 open excursion arc", gamma, P, Phi, _state_reward_matrix(rewards); start_state=1, metadata=metadata)
end

function _build_e10(params::Dict{String,String})
    gamma = _float_param(params, "gamma", 0.99)
    eps1 = _float_param(params, "eps1", 1e-2)
    eps2 = _float_param(params, "eps2", 1e-2)
    rho = _float_param(params, "rho", 1.0)
    reward_mode = _string_param(params, "reward_mode", "zero")
    P = _ring_transition_matrix(4, eps1)
    Phi = [1.0 0.0; 1.0 eps2; 0.0 1.0; -1.0 eps2] ./ sqrt(3.0)
    rewards = reward_mode == "signed-cycle" ? [0.0, rho, 0.0, -rho] : [0.0, 0.0, 0.0, 0.0]
    metadata = _format_metadata(params, ["gamma", "eps1", "eps2", "rho", "reward_mode"])
    return _finalize_environment("E10", "E10 bow-tie cycle", gamma, P, Phi, _state_reward_matrix(rewards); start_state=1, metadata=metadata)
end

function _build_e11(params::Dict{String,String})
    gamma = _float_param(params, "gamma", 0.99)
    m = _int_param(params, "m", 50)
    eps2 = _float_param(params, "eps2", 1e-2)
    rho = _float_param(params, "rho", 1.0)
    reward_mode = _string_param(params, "reward_mode", "zero")
    P = _reflecting_corridor_transition_matrix(m)
    Phi = zeros(Float64, m + 1, 2)
    cphi = sqrt((m + 1) * (1.0 + eps2^2))
    @inbounds for i in 0:m
        slope = eps2 * (2.0 * i - m) / m
        Phi[i + 1, 1] = 1.0 / cphi
        Phi[i + 1, 2] = slope / cphi
    end
    rewards = zeros(Float64, m + 1)
    if reward_mode == "linear"
        @inbounds for i in 0:m
            rewards[i + 1] = rho * (2.0 * i - m) / m
        end
    elseif reward_mode == "half-space"
        @inbounds for i in 0:m
            x = 2.0 * i - m
            rewards[i + 1] = x > 0 ? rho : (x < 0 ? -rho : 0.0)
        end
    end
    metadata = _format_metadata(params, ["gamma", "m", "eps2", "rho", "reward_mode"])
    return _finalize_environment("E11", "E11 diffusive corridor", gamma, P, Phi, _state_reward_matrix(rewards); start_state=1, metadata=metadata)
end

function _build_e12(params::Dict{String,String})
    gamma = _float_param(params, "gamma", 0.99)
    k = _int_param(params, "k", 10)
    eps1 = _float_param(params, "eps1", 1e-3)
    eps2 = _float_param(params, "eps2", 1e-2)
    rho = _float_param(params, "rho", 1.0)
    reward_mode = _string_param(params, "reward_mode", "cluster-opposite")
    n_states = 2 * k
    P = zeros(Float64, n_states, n_states)
    @inbounds for i in 1:k
        P[i, 1:k] .= (1.0 - eps1) / k
        P[i, k + 1:end] .= eps1 / k
    end
    @inbounds for i in k + 1:n_states
        P[i, 1:k] .= eps1 / k
        P[i, k + 1:end] .= (1.0 - eps1) / k
    end
    Phi = zeros(Float64, n_states, 2)
    cphi = sqrt(2.0 * k)
    @inbounds for i in 1:k
        Phi[i, 1] = 1.0 / cphi
        Phi[i, 2] = eps2 / cphi
    end
    @inbounds for i in k + 1:n_states
        Phi[i, 1] = 1.0 / cphi
        Phi[i, 2] = -eps2 / cphi
    end
    rewards = fill(rho, n_states)
    if reward_mode == "cluster-opposite"
        rewards[k + 1:end] .= -rho
    end
    metadata = _format_metadata(params, ["gamma", "k", "eps1", "eps2", "rho", "reward_mode"])
    return _finalize_environment("E12", "E12 two-cluster forcing", gamma, P, Phi, _state_reward_matrix(rewards); start_state=1, metadata=metadata)
end

@inline reset!(env::FiniteTDEnv)::Int = env.start_state
@inline phi(env::FiniteTDEnv, s::Int) = @view env.Phi[s, :]

@inline function step(env::FiniteTDEnv, s::Int, rng)
    u = rand_unit(rng)
    csum = 0.0
    s_next = env.n_states
    @inbounds for j in 1:env.n_states
        csum += env.P[s, j]
        if u <= csum
            s_next = j
            break
        end
    end
    return s_next, env.r[s, s_next]
end

function compute_objective_matrices(env::FiniteTDEnv)
    Dm = Diagonal(env.D)
    Pm = env.P
    S = Dm - 0.5 * (Dm * Pm + transpose(Pm) * Dm)
    A1 = (1.0 - env.gamma) * Dm
    A2 = A1 + env.gamma * S

    G = transpose(env.Phi) * (A1 * env.Phi)
    b = transpose(env.Phi) * (A1 * env.V_star)
    c = dot(env.V_star, A1 * env.V_star)

    G_A = transpose(env.Phi) * (A2 * env.Phi)
    b_A = transpose(env.Phi) * (A2 * env.V_star)
    c_A = dot(env.V_star, A2 * env.V_star)

    eigs = eigvals(Symmetric(G))
    lam = minimum(real.(eigs))
    lam_max = maximum(real.(eigs))
    kappa = lam > 0 ? lam_max / lam : Inf
    theta_star_sq = dot(env.theta_star, env.theta_star)
    return (; G, b, c, G_A, b_A, c_A, lambda_min=lam, kappa, theta_star_sq)
end

#########################
# Simulation & Aggregation
#########################

struct RunResult
    run_idx::Int
    diverged::Bool
    diverged_at::Int
    vbar_errs::Vector{Float64}
    vbar_errs_A::Vector{Float64}
    theta_norms::Vector{Float64}
    max_theta_norm::Float64
    final_vbar::Float64
    final_vbar_A::Float64
    final_theta_norm::Float64
end

# Keep a dense prefix and then switch to logarithmic checkpoints so downstream
# plots stay readable without materializing every timestep in memory.
function checkpoint_indices(n_steps::Int; dense_prefix::Int=100, log_step_decades::Float64=0.01)
    n_steps >= 1 || return Int[]

    keep_prefix = min(n_steps, max(dense_prefix, 1))
    checkpoints = collect(1:keep_prefix)
    factor = 10.0^log_step_decades
    last_t = keep_prefix

    while last_t < n_steps
        next_t = max(last_t + 1, ceil(Int, last_t * factor))
        next_t = min(next_t, n_steps)
        next_t == checkpoints[end] && break
        push!(checkpoints, next_t)
        last_t = next_t
    end

    checkpoints[end] == n_steps || push!(checkpoints, n_steps)
    return checkpoints
end

function run_single_simulation(alpha::Float64, run_idx::Int, n_steps::Int,
                               checkpoints::AbstractVector{<:Integer},
                               theta0::AbstractVector{<:Real}, env::FiniteTDEnv,
                               G::Matrix{Float64}, b::Vector{Float64}, c::Float64,
                               G_A::Matrix{Float64}, b_A::Vector{Float64}, c_A::Float64;
                               schedule::Symbol=:const, c_param::Float64=NaN)
    rng = SplitMix64RNG(stable_seed(alpha, run_idx))

    d = env.d
    gamma = env.gamma
    Phi = env.Phi

    vf = LinearValueFunc(d)
    @inbounds vf.w .= theta0
    theta_bar = zeros(Float64, d)

    n_checkpoints = length(checkpoints)
    vbar_errs = zeros(Float64, n_checkpoints)
    vbar_errs_A = zeros(Float64, n_checkpoints)
    theta_norms = zeros(Float64, n_checkpoints)
    checkpoint_idx = 1

    s = reset!(env)
    diverged = false
    diverged_at = -1
    max_theta = 0.0
    final_v = NaN
    final_vA = NaN
    final_theta = NaN

    phi_max_sq = 0.0
    @inbounds for ii in 1:env.n_states
        accp = 0.0
        @inbounds @simd for jj in 1:d
            accp += Phi[ii, jj] * Phi[ii, jj]
        end
        phi_max_sq = max(phi_max_sq, accp)
    end

    @inbounds for t in 1:n_steps
        s_next, reward = step(env, s, rng)

        dot_phi = 0.0
        dot_phi_next = 0.0
        @inbounds @simd for j in 1:d
            wj = vf.w[j]
            dot_phi += wj * Phi[s, j]
            dot_phi_next += wj * Phi[s_next, j]
        end
        delta = reward + gamma * dot_phi_next - dot_phi

        alpha_eff = alpha
        if schedule == :theory
            cval = isfinite(c_param) ? c_param : 1.0
            denom = cval * max(phi_max_sq, 1e-12) * max(log(n_steps), 1.0) * log(t + 3.0) * sqrt(t + 1.0)
            alpha_eff = 1.0 / denom
        end

        @inbounds @simd for j in 1:d
            vf.w[j] += alpha_eff * delta * Phi[s, j]
        end

        invt = 1.0 / t
        @inbounds @simd for j in 1:d
            theta_bar[j] += (vf.w[j] - theta_bar[j]) * invt
        end

        q = 0.0
        @inbounds for i in 1:d
            acc = 0.0
            @inbounds @simd for j in 1:d
                acc += G[i, j] * theta_bar[j]
            end
            q += theta_bar[i] * acc
        end
        vbar = q - 2.0 * dot(theta_bar, b) + c

        qA = 0.0
        @inbounds for i in 1:d
            accA = 0.0
            @inbounds @simd for j in 1:d
                accA += G_A[i, j] * theta_bar[j]
            end
            qA += theta_bar[i] * accA
        end
        vbarA = qA - 2.0 * dot(theta_bar, b_A) + c_A

        theta_n2 = 0.0
        @inbounds @simd for j in 1:d
            theta_n2 += vf.w[j] * vf.w[j]
        end

        if theta_n2 > max_theta
            max_theta = theta_n2
        end

        final_v = vbar
        final_vA = vbarA
        final_theta = theta_n2
        if checkpoint_idx <= n_checkpoints && t == checkpoints[checkpoint_idx]
            vbar_errs[checkpoint_idx] = vbar
            vbar_errs_A[checkpoint_idx] = vbarA
            theta_norms[checkpoint_idx] = theta_n2
            checkpoint_idx += 1
        end

        if theta_n2 > 1.0e12 || !isfinite(theta_n2)
            diverged = true
            diverged_at = t
        end

        s = s_next
    end

    final_v = diverged ? Inf : final_v
    final_vA = diverged ? Inf : final_vA
    final_theta = diverged ? Inf : final_theta
    return RunResult(run_idx, diverged, diverged_at, vbar_errs, vbar_errs_A, theta_norms, max_theta, final_v, final_vA, final_theta)
end

function aggregate_results(results::Vector{RunResult}, checkpoints::AbstractVector{<:Integer})
    n_runs = length(results)
    nT = Threads.nthreads()
    n_checkpoints = length(checkpoints)

    sums_vbar = [zeros(Float64, n_checkpoints) for _ in 1:nT]
    sums_vbar2 = [zeros(Float64, n_checkpoints) for _ in 1:nT]
    sums_vbar_A = [zeros(Float64, n_checkpoints) for _ in 1:nT]
    sums_vbar_A2 = [zeros(Float64, n_checkpoints) for _ in 1:nT]
    sums_theta = [zeros(Float64, n_checkpoints) for _ in 1:nT]
    sums_theta2 = [zeros(Float64, n_checkpoints) for _ in 1:nT]
    counts = [zeros(Int32, n_checkpoints) for _ in 1:nT]

    Threads.@threads for i in 1:n_runs
        tid = threadid()
        r = results[i]
        vb = r.vbar_errs
        vba = r.vbar_errs_A
        th = r.theta_norms
        sv = sums_vbar[tid]
        sv2 = sums_vbar2[tid]
        sva = sums_vbar_A[tid]
        sva2 = sums_vbar_A2[tid]
        st = sums_theta[tid]
        st2 = sums_theta2[tid]
        ct = counts[tid]
        @inbounds @simd for idx in 1:n_checkpoints
            v = vb[idx]
            va = vba[idx]
            tnv = th[idx]
            if isfinite(v) && isfinite(va) && isfinite(tnv)
                sv[idx] += v
                sv2[idx] += v * v
                sva[idx] += va
                sva2[idx] += va * va
                st[idx] += tnv
                st2[idx] += tnv * tnv
                ct[idx] += 1
            end
        end
    end

    avg_vbar = Vector{Float64}(undef, n_checkpoints)
    std_vbar = Vector{Float64}(undef, n_checkpoints)
    avg_vbar_A = Vector{Float64}(undef, n_checkpoints)
    std_vbar_A = Vector{Float64}(undef, n_checkpoints)
    avg_theta_norms = Vector{Float64}(undef, n_checkpoints)
    std_theta_norms = Vector{Float64}(undef, n_checkpoints)

    @inbounds for idx in 1:n_checkpoints
        sv = 0.0
        svsq = 0.0
        st = 0.0
        stsq = 0.0
        cnt = 0
        @inbounds @simd for k in 1:nT
            sv += sums_vbar[k][idx]
            svsq += sums_vbar2[k][idx]
            st += sums_theta[k][idx]
            stsq += sums_theta2[k][idx]
            cnt += counts[k][idx]
        end
        av = sv / max(cnt, 1)
        ava = 0.0
        avasq = 0.0
        @inbounds @simd for k in 1:nT
            ava += sums_vbar_A[k][idx]
            avasq += sums_vbar_A2[k][idx]
        end
        ava /= max(cnt, 1)
        ex2 = svsq / max(cnt, 1)
        std_vbar[idx] = sqrt(max(0.0, ex2 - av * av))
        ea2 = avasq / max(cnt, 1)
        std_vbar_A[idx] = sqrt(max(0.0, ea2 - ava * ava))
        at = st / max(cnt, 1)
        ea2_theta = stsq / max(cnt, 1)
        std_theta_norms[idx] = sqrt(max(0.0, ea2_theta - at * at))
        avg_vbar[idx] = av
        avg_vbar_A[idx] = ava
        avg_theta_norms[idx] = at
    end

    t0 = findmax(avg_theta_norms)[2]
    max_avg_theta = avg_theta_norms[t0]
    max_std_theta = std_theta_norms[t0]
    diverged_count = count(r -> r.diverged, results)

    return (; timesteps=Int[checkpoints...], avg_vbar, std_vbar, avg_vbar_A, std_vbar_A, avg_theta_norms, max_avg_theta, max_std_theta,
              diverged=diverged_count, divergence_rate=diverged_count / max(n_runs, 1))
end

end # module
