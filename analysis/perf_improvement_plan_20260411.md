# C++ TD Experiment Performance Improvement Plan (2026-04-11)

## Scope
- Code inspected: `/home/leew0a/codex/TDfullexperiments/cpp/tdx.cpp`, `/home/leew0a/codex/TDfullexperiments/cpp/Makefile`
- Goal: speed up large experiment runs (`1e7` to `1e9` steps, 40+ Monte Carlo runs, large method/c-sweep grids)
- Constraint: prioritize changes that preserve current outputs and experiment semantics

## High-level diagnosis
The main runtime is concentrated in the inner loop of:
- [tdx.cpp](/home/leew0a/codex/TDfullexperiments/cpp/tdx.cpp#L1519)

Current per-step work includes:
1. transition sampling over a dense row CDF
2. two dot products for `phi(s)` and `phi(s')`
3. weight update
4. optional projection norm check
5. running average update for `theta_bar`
6. objective evaluation for `D`
7. objective evaluation for `D+A`
8. full `||theta_t||^2` recomputation

That is much more work than what is actually required for the stored outputs.

## Most important observation
The code currently computes `vbar` and `vbarA` at **every single step**:
- [tdx.cpp:1585](/home/leew0a/codex/TDfullexperiments/cpp/tdx.cpp#L1585)
- [tdx.cpp:1595](/home/leew0a/codex/TDfullexperiments/cpp/tdx.cpp#L1595)

But those values are only written out at checkpoints and the final time:
- [tdx.cpp:1611](/home/leew0a/codex/TDfullexperiments/cpp/tdx.cpp#L1611)
- checkpoints are sparse after the dense prefix; for `n_steps = 1e8`, the default checkpoint count is only `692`

So right now, the code does `O(d^2)` objective work `1e8` times per run even though it only needs it about `692` times.

This is the highest-value optimization by far.

## Priority table

| Priority | Change | Expected payoff | Risk | Output compatibility |
|---|---|---|---|---|
| P0 | Compute `D` / `D+A` only at checkpoints and final step | very high | low | should be identical |
| P0 | Replace dense-row transition scan with sparse-row sampler | high | low to medium | can be identical if CDF semantics preserved |
| P0 | Maintain `||theta_t||^2` incrementally instead of full inner product each step | medium to high | low | numerically extremely close |
| P1 | Specialize runner by schedule/projection to remove per-step switch/branch overhead | medium | medium | identical |
| P1 | Rework aggregation to avoid per-run checkpoint vectors and repeated allocations | medium | medium | identical |
| P1 | Add `-flto` and optionally PGO build path | low to medium | low | identical |
| P2 | Use alias sampling instead of CDF sampling | medium | medium to high | may change exact random path |
| P2 | SIMD / manual vectorization / BLAS-style kernels | medium | medium to high | identical or near-identical |

## P0. Compute objectives only at checkpoints

### Current issue
Inside the hot loop, the code computes
- `q = theta_bar^T G theta_bar`
- `qA = theta_bar^T G_A theta_bar`

at every `t`:
- [tdx.cpp:1585-1603](/home/leew0a/codex/TDfullexperiments/cpp/tdx.cpp#L1585)

This is unnecessary because outputs are only stored when `t` is a checkpoint.

### Why this matters
For `d = 20`, each objective evaluation costs roughly `O(d^2)`.
You currently do this twice per step (`G` and `G_A`).

For `n_steps = 1e8`:
- current: about `1e8` objective evaluations per run
- needed: about `692` checkpoint evaluations per run

That is a reduction by about `1.4e5x` in the number of objective evaluations.

### Expected effect
- On `d = 20` environments (`E4`, `E5`), this should be the single biggest speedup.
- On `d = 2` environments, the benefit is smaller but still free.

### Recommended implementation
Inside `run_single_simulation`:
1. keep updating `theta_bar` every step
2. compute `vbar` and `vbarA` only if
   - `t == checkpoints[cp_idx]`, or
   - divergence is being reported and you still want a last finite value before divergence
3. otherwise skip all `G` / `G_A` quadratic forms

### Compatibility
This should preserve the CSV outputs exactly, because only checkpoint values are written.

## P0. Replace dense transition scan with sparse transition sampling

### Current issue
Transition sampling uses a dense row CDF and scans the whole row linearly:
- [tdx.cpp:1505-1516](/home/leew0a/codex/TDfullexperiments/cpp/tdx.cpp#L1505)
- dense CDF is built here: [tdx.cpp:727-744](/home/leew0a/codex/TDfullexperiments/cpp/tdx.cpp#L727)

That means even if a row has only 2 or 3 nonzero transitions, the sampler still scans all `n_states` entries.

### Why this matters for your instances
Many environments are sparse by construction:
- `toyexample`: support size about 3 per row
- `E4`: support size 2 per row
- `E5`: support size 1 or 2 per row
- `E7`: support size 2 per row
- `E9`: support size 2 or 3 per row

But current code scans up to `n=50` or `n=65` entries every step.

### Recommended implementation
Precompute a sparse row sampler per state:
- `next_state_idx[row]`: list of nonzero next states
- `next_state_cdf[row]`: cumulative masses over only those nonzero entries
- `reward_support[row]`: rewards aligned with the support

Then sample using:
- linear scan over support if support is tiny (2 or 3), or
- `std::lower_bound` on row-local CDF if support is larger

### Compatibility
If you preserve the same cumulative order and use the same `u`, this can preserve the current sampling semantics exactly.
So this is a safe optimization if implemented carefully.

## P0. Maintain `||theta_t||^2` incrementally

### Current issue
The code recomputes `||theta_t||^2` by full inner product every step:
- [tdx.cpp:1605](/home/leew0a/codex/TDfullexperiments/cpp/tdx.cpp#L1605)
- it also recomputes the norm during projection: [tdx.cpp:1567-1576](/home/leew0a/codex/TDfullexperiments/cpp/tdx.cpp#L1567)

### Better formula
If
- `w_new = w + beta * phi_s`
- `beta = alpha * delta`

then
- `||w_new||^2 = ||w||^2 + 2 * beta * <w, phi_s> + beta^2 * ||phi_s||^2`

and `<w, phi_s>` is already computed as `dot_phi`.

### Recommended implementation
Precompute per-state
- `phi_row_sq[s] = ||phi(s)||^2`

Then maintain a scalar `theta_n2` through the loop.
For projected runs:
- if clipping occurs, just set `theta_n2 = proj_R^2`

### Expected effect
This removes one `O(d)` dot product every step.
It is not as large as the objective-skipping gain, but it is clean and worthwhile.

### Compatibility
Numerically this should be extremely close.
It may not be bitwise identical due to different floating-point evaluation order.

## P1. Specialize the hot loop by schedule and projection

### Current issue
Each step currently pays for:
- a schedule `switch` in `alpha_t`: [tdx.cpp:1398-1434](/home/leew0a/codex/TDfullexperiments/cpp/tdx.cpp#L1398)
- a projection branch: [tdx.cpp:1567](/home/leew0a/codex/TDfullexperiments/cpp/tdx.cpp#L1567)

### Recommended implementation
Dispatch once per configuration into specialized runners, for example:
- `run_simulation<ScheduleType::Theory, ProjectionType::None>`
- `run_simulation<ScheduleType::InvT, ProjectionType::Oracle>`

Benefits:
- removes branch/switch traffic from the inner loop
- lets compiler inline more aggressively
- makes it easier to precompute schedule constants outside the loop

### Expected effect
Likely a moderate speedup, especially after the bigger structural bottlenecks are fixed.

## P1. Aggregate online instead of storing checkpoint vectors per run

### Current issue
Each `RunResult` owns 3 vectors of length `n_checkpoints`:
- [tdx.cpp:1444-1455](/home/leew0a/codex/TDfullexperiments/cpp/tdx.cpp#L1444)
- allocated here: [tdx.cpp:1537-1540](/home/leew0a/codex/TDfullexperiments/cpp/tdx.cpp#L1537)

Then `aggregate_results` makes a second pass over all runs:
- [tdx.cpp:1640+](/home/leew0a/codex/TDfullexperiments/cpp/tdx.cpp#L1640)

### Recommended implementation
Use per-thread accumulation buffers during the OpenMP loop:
- sums for `D`, `D+A`, `theta_norm`
- sums of squares for std
- alpha summaries
- divergence count

Only keep per-run scalar summaries that are needed for `runs_*.csv`:
- `diverged`
- `diverged_at`
- `final_obj_D`
- `final_obj_A`
- `final_theta_norm`
- `max_theta_norm`
- `max_alpha`
- `proj_clip_count`

### Expected effect
- fewer heap allocations
- less memory traffic
- less post-processing

This is useful, but lower priority than the checkpoint-only objective fix.

## P1. Build-system improvements
Current flags are already decent:
- [Makefile:1-18](/home/leew0a/codex/TDfullexperiments/cpp/Makefile#L1)

### Recommended additions
1. add LTO build option
   - `-flto`
2. add a PGO workflow for representative sweeps
   - instrumented build
   - run one representative benchmark sweep
   - optimized rebuild using generated profile
3. add `-DNDEBUG`

### Expected effect
Usually low-to-medium, but easy relative to deeper refactors.

## P2. Alias sampler

### Why it may help
After fixing objective evaluation, transition sampling may become the dominant cost for `d=2, n=50~65` cases.
An alias sampler gives `O(1)` expected sampling time.

### Why it is not first
It may change the exact random trajectory, even if the marginal distribution is identical.
Given your earlier insistence on RNG correctness and C++/Julia comparability, I would not do this first.

## P2. SIMD / vectorization pass

### Candidates
- fused dot/update loop for `phi(s)` and `phi(s')`
- manual row-pointer kernels for `Phi`
- `#pragma omp simd` on small fixed loops

### Why lower priority
These help only after removing the big structural waste.
Right now the code is leaving much larger wins on the table.

## Recommended execution order

### Phase A: do first
1. checkpoint-only `D` / `D+A` computation
2. sparse transition sampler with identical CDF semantics
3. incremental `||theta_t||^2`

### Phase B: do next
4. specialize runner by schedule/projection
5. online aggregation / buffer reuse
6. LTO + optional PGO

### Phase C: only if still needed
7. alias sampler
8. SIMD / deeper micro-optimizations

## Expected qualitative outcome
If you only do Phase A, I expect:
- substantial speedup on `E4` and `E5`
- clear speedup on `toyexample`, `E7`, `E9`
- lower CPU waste across the whole full sweep

The single highest-confidence change is still:
- **stop evaluating `D` and `D+A` at every step**

## What I would implement first
If you want me to patch the code next, I would start with:
1. checkpoint-only objective evaluation
2. sparse transition sampler
3. incremental theta norm maintenance

That sequence gives the best payoff-to-risk ratio.
