module TDThreshold

using LinearAlgebra
using Random
using Printf
using Base.Threads

# Deterministic per-run seed without relying on session hash
@inline function stable_seed(alpha::Float64, run_idx::Int)
    a = reinterpret(UInt64, alpha)
    b = UInt64(run_idx)
    z = (a * 0x9E3779B97F4A7C15) ⊻ (b * 0xD2B74407B1CE6E93) ⊻ 0x94D049BB133111EB
    return Int(mod(z, UInt64(0x7fffffff))) + 1
end

###############################
# Linear FA: v(s) = w' * phi(s)
###############################
mutable struct LinearValueFunc
    w::Vector{Float64}
end

LinearValueFunc(d::Integer) = LinearValueFunc(zeros(d))

@inline value(vf::LinearValueFunc, phi::AbstractVector{<:Real})::Float64 = dot(vf.w, phi)

@inline function update_td0!(vf::LinearValueFunc, alpha::Float64,
                             phi::AbstractVector{<:Real}, r::Float64,
                             phi_next::AbstractVector{<:Real}, gamma::Float64)
    delta = r + gamma * dot(vf.w, phi_next) - dot(vf.w, phi)
    @inbounds @simd for i in eachindex(vf.w)
        vf.w[i] += alpha * delta * phi[i]
    end
    return nothing
end

#########################
# ToyExample MDP (tabular dynamics, linear features)
#########################
mutable struct ToyExampleMDP
    gamma::Float64
    n_states::Int
    d::Int
    P::Matrix{Float64}
    D::Vector{Float64}          
    Phi::Matrix{Float64}
    theta_star::Vector{Float64}
    V_star::Vector{Float64}
    r::Matrix{Float64}
    rng::MersenneTwister
end

function ToyExampleMDP(; gamma::Float64=0.99, seed::Int=114514, scale_factor::Float64=1.0)
    n_states = 50
    d = 5

    reward_rng = MersenneTwister(seed)

    P = zeros(Float64, n_states, n_states)
    @inbounds for i in 1:n_states
        P[i, i] = 0.1
        P[i, (i % n_states) + 1] = 0.6 # i -> i+1
        P[i, ((i - 2 + n_states) % n_states) + 1] = 0.3 # i -> i-1
    end

    # Stationary distribution from eigvec of P'
    eigvals, eigvecs = eigen(transpose(P))
    idx = argmin(abs.(eigvals .- 1.0))
    stat = abs.(eigvecs[:, idx])
    D = vec(stat ./ sum(stat))
    Dm = Diagonal(D)

    # Sample reward first so the MDP is fixed before choosing features
    r = rand(reward_rng, n_states, n_states)

    feature_rng = MersenneTwister(seed)
    Phi = rand(feature_rng, n_states, d)*10
    if scale_factor <= 1.0
        @views Phi[:, 1] .*= scale_factor
    else
        @views Phi[:, 1:end]  .*= scale_factor
    end
    # Expected immediate reward per state: r̄(s) = Σ_{s'} P(s,s') r(s,s')
    r_bar = vec(sum(P .* r, dims=2))
    M = I - gamma * P
    A = Phi' * Dm * M * Phi
    b = Phi' * Dm * r_bar
    theta_star = A \ b
    V_star = Phi * theta_star

    return ToyExampleMDP(gamma, n_states, d, P, D, Phi, theta_star, V_star, r, feature_rng)
end

@inline reset!(env::ToyExampleMDP)::Int = 1 # start from state index 1 (arbitrary)

@inline function step(env::ToyExampleMDP, s::Int)
    # categorical sample from row P[s, :]
    p = @view env.P[s, :]
    u = rand(env.rng)
    c = 0.0
    @inbounds for j in 1:length(p)
        c += p[j]
        if u <= c
            return j, env.r[s, j] # reward depends on (s, s_next)
        end
    end
    return length(p), env.r[s, length(p)] # fallback due to FP rounding
end

@inline phi(env::ToyExampleMDP, s::Int) = @view env.Phi[s, :]

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

function run_single_simulation(alpha::Float64, run_idx::Int, n_steps::Int,
                               theta0::AbstractVector{<:Real}, env::ToyExampleMDP,
                               G::Matrix{Float64}, b::Vector{Float64}, c::Float64,
                               G_A::Matrix{Float64}, b_A::Vector{Float64}, c_A::Float64;
                               schedule::Symbol=:const, c_param::Float64=NaN)
    # Independent RNG per run
    rng = MersenneTwister(stable_seed(alpha, run_idx))

    d = env.d
    gamma = env.gamma
    Phi = env.Phi
    rmat = env.r

    # Initialize VF and running average theta_bar
    vf = LinearValueFunc(d)
    @inbounds vf.w .= theta0
    theta_bar = zeros(Float64, d)

    vbar_errs = zeros(Float64, n_steps)
    vbar_errs_A = zeros(Float64, n_steps)
    theta_norms = zeros(Float64, n_steps)

    s = 1
    diverged = false
    diverged_at = -1
    max_theta = 0.0

    # For time-varying schedule we need max ||phi||^2 over states
    phi_max_sq = 0.0
    @inbounds for ii in 1:env.n_states
        accp = 0.0
        @inbounds @simd for jj in 1:d
            accp += Phi[ii, jj]*Phi[ii, jj]
        end
        phi_max_sq = max(phi_max_sq, accp)
    end

    @inbounds for t in 1:n_steps
        # Sample next state from row env.P[s, :] without creating a view
        u = rand(rng)
        csum = 0.0
        s_next = 1
        @inbounds for j in 1:env.n_states
            csum += env.P[s, j]
            if u <= csum
                s_next = j
                break
            end
        end
        dot_phi = 0.0
        dot_phi_next = 0.0
        @inbounds @simd for j in 1:d
            wj = vf.w[j]
            dot_phi      += wj * Phi[s, j]
            dot_phi_next += wj * Phi[s_next, j]
        end
        delta = rmat[s, s_next] + gamma * dot_phi_next - dot_phi

        # step-size 
        alpha_eff = alpha
        if schedule == :theory
            cval = isfinite(c_param) ? c_param : 1.0
            denom = cval * max(phi_max_sq, 1e-12) * max(log(n_steps), 1.0) * log(t + 3.0) * sqrt(t + 1.0)
            alpha_eff = 1.0 / denom
        end

        # step-size-fixed
        # alpha_eff = alpha
        # if schedule == :theory
        #     cval = isfinite(c_param) ? c_param : 1.0
        #     denom = cval * max(phi_max_sq, 1e-12) * max(log(n_steps), 1.0) * log(n_steps + 3.0) * sqrt(n_steps + 1.0)
        #     alpha_eff = 1.0 / denom
        # end

        @inbounds @simd for j in 1:d
            vf.w[j] += alpha_eff * delta * Phi[s, j]
        end

        # Incremental running average of theta
        invt = 1.0 / t
        @inbounds @simd for j in 1:d
            theta_bar[j] += (vf.w[j] - theta_bar[j]) * invt
        end

        # vbar(theta_bar) = theta_bar' G theta_bar − 2 theta_bar' b + c
        q = 0.0
        @inbounds for i in 1:d
            acc = 0.0
            @inbounds @simd for j in 1:d
                acc += G[i, j] * theta_bar[j]
            end
            q += theta_bar[i] * acc
        end
        vbar = q - 2.0 * dot(theta_bar, b) + c
        # New objective
        qA = 0.0
        @inbounds for i in 1:d
            accA = 0.0
            @inbounds @simd for j in 1:d
                accA += G_A[i, j] * theta_bar[j]
            end
            qA += theta_bar[i] * accA
        end
        vbarA = qA - 2.0 * dot(theta_bar, b_A) + c_A

        vbarA = gamma * vbarA
        vbar = (1.0 - gamma) * vbar 

        theta_n2 = 0.0
        @inbounds @simd for j in 1:d
            theta_n2 += vf.w[j] * vf.w[j]
        end

        if theta_n2 > max_theta
            max_theta = theta_n2
        end

        vbar_errs[t] = vbar
        vbar_errs_A[t] = vbarA
        theta_norms[t] = theta_n2

        if theta_n2 > 1.0e12 || !isfinite(theta_n2)
            diverged = true
            diverged_at = t
        end

        s = s_next
    end

    final_v = diverged ? Inf : vbar_errs[end]
    final_vA = diverged ? Inf : vbar_errs_A[end]
    final_theta = diverged ? Inf : theta_norms[end]
    return RunResult(run_idx, diverged, diverged_at, vbar_errs, vbar_errs_A, theta_norms, max_theta, final_v, final_vA, final_theta)
end

function aggregate_results(results::Vector{RunResult}, n_steps::Int)

    n_runs = length(results)
    nT = Threads.nthreads()

    sums_vbar = [zeros(Float64, n_steps) for _ in 1:nT]
    sums_vbar2 = [zeros(Float64, n_steps) for _ in 1:nT]
    sums_vbar_A = [zeros(Float64, n_steps) for _ in 1:nT]
    sums_vbar_A2 = [zeros(Float64, n_steps) for _ in 1:nT]
    sums_theta = [zeros(Float64, n_steps) for _ in 1:nT]
    sums_theta2 = [zeros(Float64, n_steps) for _ in 1:nT]
    counts = [zeros(Int32, n_steps) for _ in 1:nT]

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
        @inbounds @simd for t in 1:n_steps
            v = vb[t]
            sv[t] += v
            sv2[t] += v * v
            sva[t] += vba[t]
            sva2[t] += vba[t] * vba[t]
            st[t] += th[t]
            st2[t] += th[t] * th[t]
            ct[t] += 1
        end
    end

    avg_vbar = Vector{Float64}(undef, n_steps)
    std_vbar = Vector{Float64}(undef, n_steps)
    avg_vbar_A = Vector{Float64}(undef, n_steps)
    std_vbar_A = Vector{Float64}(undef, n_steps)
    avg_theta_norms = Vector{Float64}(undef, n_steps)
    std_theta_norms = Vector{Float64}(undef, n_steps)
    max_avg_theta = 0.0
    max_std_theta = 0.0


    @inbounds for t in 1:n_steps
        sv = 0.0
        svsq = 0.0
        st = 0.0
        stsq = 0.0
        cnt = 0
        @inbounds @simd for k in 1:nT
            sv   += sums_vbar[k][t]
            svsq += sums_vbar2[k][t]
            st   += sums_theta[k][t]
            stsq += sums_theta2[k][t]
            cnt  += counts[k][t]
        end
        av = sv / max(cnt, 1)
        # combine across threads for A
        ava = 0.0
        avasq = 0.0
        @inbounds @simd for k in 1:nT
            ava   += sums_vbar_A[k][t]
            avasq += sums_vbar_A2[k][t]
        end
        ava /= max(cnt, 1)
        # std with population variance: sqrt(E[x^2] - (E[x])^2)
        ex2 = svsq / max(cnt, 1)
        std_vbar[t] = sqrt(max(0.0, ex2 - av*av))
        ea2 = avasq / max(cnt, 1)
        std_vbar_A[t] = sqrt(max(0.0, ea2 - ava*ava))
        at = st / max(cnt, 1)
        ea2_theta = stsq / max(cnt, 1)
        std_theta_norms[t] = sqrt(max(0.0, ea2_theta - at*at))
        avg_vbar[t] = av
        avg_vbar_A[t] = ava
        avg_theta_norms[t] = at
    end
    # Use the time index where the average theta-norm is maximized to define ratio stats
    t0 = findmax(avg_theta_norms)[2]
    max_avg_theta = avg_theta_norms[t0]
    max_std_theta = std_theta_norms[t0]


    diverged_count = count(r -> r.diverged, results)
    return (; avg_vbar, std_vbar, avg_vbar_A, std_vbar_A, avg_theta_norms, max_avg_theta, max_std_theta,diverged=diverged_count,
              divergence_rate = diverged_count / n_runs)
end

end # module
