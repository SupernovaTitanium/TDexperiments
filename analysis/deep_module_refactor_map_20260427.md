# Deep Module Refactor Map (2026-04-27)

## Goal

Improve locality and leverage without changing TD experiment semantics or output files.

This map uses the architecture vocabulary from the repo optimization pass:

- a Module has an Interface and an Implementation
- a Seam is where that Interface lives
- a deep Module hides substantial behavior behind a small Interface

## Current Friction

`cpp/tdx.cpp` currently contains these responsibilities in one file:

1. command-line and config parsing
2. environment-family defaults and Case construction
3. finite-state numerics and TD objective construction
4. Schedule and Projection parsing/semantics
5. Monte Carlo simulation
6. aggregation
7. CSV writing and manifest writing
8. optional Python plot launcher

The file is workable, but it has low locality: a change to one domain concept can require reading unrelated CLI, numerics, and output code.

## Deepening Opportunities

| Candidate Module | Proposed Interface | Hidden Implementation | Benefit |
| --- | --- | --- | --- |
| TD Instance Catalog | `build_cases(env_id, set_params, sweep_params, dedup_policy)` | environment defaults, parameter product, omega dedup, environment builders | Keeps Environment Family and Case logic local. |
| Method Spec | `parse_methods(schedules, projections, c_values)` and `alpha_t(method, t, context)` | Schedule parsing, Projection parsing, stepsize formulas, projection radius | Prevents schedule/projection/report drift. |
| Simulation Runner | `run_method_case(case, method, run_config)` | RNG, transition sampling, TD update, projection, checkpoint logging | Makes hot-loop changes testable through one seam. |
| Result Aggregator | `aggregate_runs(runs, checkpoints, method, case)` | finite filtering, std convention, alpha columns | Protects baseline aggregation semantics. |
| Output Contract | `write_manifest(rows)` / `write_case_outputs(row, runs, aggregate)` | CSV column order, formatting, filenames | Makes schema preservation explicit. |
| Plot Report Reader | `load_manifest_run(run_dir)` | manifest parsing, file lookup, method/case sorting | Reduces duplicate parsing assumptions in plot/report scripts. |

## Recommended Refactor Order

1. Add and run the exactness gate before any C++ split.
2. Extract Output Contract helpers first because the Interface is already public and stable. This is started in `cpp/tdx_output_contract.hpp`.
3. Extract Method Spec next because schedule/projection definitions are duplicated in C++, plots, reports, and README.
4. Extract TD Instance Catalog after Method Spec because it has many environment-specific branches.
5. Extract Simulation Runner last because it is the highest-risk hot loop.

## Rejected for Default Implementation

Do not reintroduce these as default refactors:

- incremental `theta_n2` maintenance
- alternative aggregation semantics
- compiled alpha replacement if it changes floating-point order
- alias sampling that changes transition RNG path

These may be useful experimental branches only if the acceptance criterion changes from byte-identical exactness to tolerance-based equivalence.

## Acceptance Criteria

Each refactor step must:

1. preserve `./cpp/tdx sweep` CLI behavior
2. preserve manifest schema and CSV schemas
3. pass `scripts/verify_exactness_gate.py` on `toyexample,E10`
4. pass a broader 11-family gate when simulation, aggregation, schedule, projection, or output code changes
5. record any benchmark or exactness result in `analysis/`
