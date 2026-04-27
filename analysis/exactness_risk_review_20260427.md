# Exactness Risk Review (2026-04-27)

## Scope

This review covers the current C++-first TD workflow:

- `cpp/tdx.cpp`
- `cpp/Makefile`
- `scripts/plot_suite_v2.py`
- `scripts/generate_embedded_report_v2.py`

The goal is not style review. The goal is to identify correctness risks that can invalidate byte-for-byte exactness, deterministic reproducibility, or downstream plot/report interpretation.

## Execution Model

- Language: C++17 for the engine, Python 3 for plotting/report scripts.
- Build flags: `-O3 -std=c++17 -march=native -ffast-math -fopenmp -Wall -Wextra -Wpedantic`.
- Runtime: OpenMP parallel Monte Carlo over runs with `schedule(static)`.
- Shared mutable state in hot loop: each OpenMP worker writes a unique `runs[run_idx]` slot.
- Output contract: `manifest.tsv`, `runs_case_*.csv`, and `agg_case_*.csv` are the source of truth.
- Exactness requirement: byte-identical output against the current exactness baseline.

## Established Properties

| Property | Logical Status | Evidence Status | Notes |
| --- | --- | --- | --- |
| RNG seed depends only on `c` and `run_idx` | Established under source inspection | Verified by inspection | `stable_seed(spec.param, run_idx)` does not depend on thread count. |
| Monte Carlo run ordering is deterministic under static scheduling | Established under assumptions | Partially verified | Each worker writes a unique index; aggregation iterates `runs` in index order. |
| Manifest points to relative CSV filenames | Established under source inspection | Verified by inspection | `agg_file` and `run_file` are names, not absolute paths. |
| Projection is selected once per Method | Established under source inspection | Verified by inspection | Dispatch goes through `select_run_simulation_fn`. |
| Objectives are computed only at checkpoints | Established under source inspection | Verified by inspection | This is already in the production hot loop. |
| Aggregation uses baseline-compatible finite filtering | Established under source inspection | Partially verified | The previous exactness reports validate this over 44 cases. |

## Primary Risks

| Risk | Severity | Confidence | Trigger | Fix Direction |
| --- | --- | --- | --- | --- |
| `-ffast-math` can change NaN/Inf behavior or reassociate floating-point operations | High | High | Compiler, CPU, or flag changes around divergence/finite checks | Keep exactness gate mandatory for any build-flag change; consider a separate strict build target for verification. |
| Any change to floating-point evaluation order can break byte exactness | High | High | Incremental norm, online aggregation, compiled alpha replacement | Keep these optimizations disabled by default unless the user accepts tolerance-based matching. |
| Output schema changes can silently break plotting/report scripts | High | High | Renaming CSV columns or manifest fields | Treat `manifest.tsv`, `runs_case_*.csv`, and `agg_case_*.csv` as public interfaces. |
| Adding schedules/projections can desynchronize C++, plot labels, report labels, and README | Medium | High | New method added only in `tdx.cpp` | Add tests that inspect generated manifest methods and generated report method definitions. |
| Environment-family defaults can drift from launch scripts | Medium | Medium | Changing defaults in `tdx.cpp` without updating scripts/docs | Treat `cpp/tdx.cpp` as source of truth and regenerate docs or validation notes after changes. |
| Plot code can accidentally assume exactly four Cases | Medium | Medium | New omega levels or dedup behavior changes | Keep plot tests using variable case counts. |

## Verification Obligations for Future Engine Changes

1. Rebuild with `make -C cpp`.
2. Run `scripts/verify_exactness_gate.py` on `toyexample,E10`.
3. If simulation semantics, RNG, aggregation, projection, stepsize, or output schema changed, compare against a saved baseline binary or saved baseline output.
4. If plots/reports changed, run `scripts/verify_exactness_gate.py --plot-check` or directly run the v2 plot/report commands.
5. For substantive performance changes, write an `analysis/` report with timing and exactness results.

## Current Review Conclusion

The safest next architecture move is to deepen seams only after the public-interface exactness gate exists. The highest-risk code is not the module structure itself; it is the combination of floating-point exactness, divergence handling, RNG path, and output schema compatibility.
