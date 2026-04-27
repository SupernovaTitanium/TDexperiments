#!/usr/bin/env python3
"""Public-interface exactness gate for the C++ TD engine.

The gate compares two `./cpp/tdx sweep` executions. By default it runs the same
binary twice, which checks deterministic self-consistency. For refactors or
performance work, pass an older binary as `--baseline-bin` and the edited binary
as `--candidate-bin`.
"""

from __future__ import annotations

import argparse
import filecmp
import os
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path


ALL_SCHEDULES = "theory,theory_log2,constant_omega,constant,inv_t,inv_sqrt_t,inv_t_2_3,inv_omega_t"
ALL_PROJECTIONS = "none,oracle,upper"
DEFAULT_ENVS = "toyexample,E10"
REPO_DANGEROUS_NAMES = {"", ".", ".."}

ENV_EXTRA_ARGS: dict[str, list[str]] = {
    "toyexample": ["--set", "scale_factor=1.0", "--set", "seed=114514"],
    "E1": ["--set", "reward_mode=driven", "--set", "rho=1.0"],
    "E2": ["--set", "reward_mode=driven", "--set", "rho=1.0"],
    "E3": ["--set", "reward_mode=signed", "--set", "rho=1.0"],
    "E4": ["--set", "reward_mode=single-site", "--set", "rho=1.0"],
    "E5": ["--set", "reward_mode=launch", "--set", "rho=1.0"],
    "E6": ["--set", "reward_mode=single-harmonic", "--set", "rho=1.0"],
    "E7": ["--set", "reward_mode=uniform", "--set", "rho=1.0"],
    "E8": ["--set", "reward_mode=signed-cycle", "--set", "rho=1.0"],
    "E9": ["--set", "reward_mode=linear", "--set", "rho=1.0"],
    "E10": ["--set", "reward_mode=cluster-opposite", "--set", "rho=1.0"],
}


@dataclass(frozen=True)
class CompareResult:
    env: str
    total_files: int
    diff_files: int
    missing_files: int
    elapsed_baseline_s: float
    elapsed_candidate_s: float


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Run and compare exactness gates for cpp/tdx")
    p.add_argument("--baseline-bin", default="./cpp/tdx", help="Reference tdx binary")
    p.add_argument("--candidate-bin", default="./cpp/tdx", help="Candidate tdx binary")
    p.add_argument("--work-root", default="/tmp/tdx_exactness_gate", help="Temporary output root")
    p.add_argument("--envs", default=DEFAULT_ENVS, help="Comma-separated environment families")
    p.add_argument("--n-steps", type=int, default=1000, help="Steps per Monte Carlo run")
    p.add_argument("--n-runs", type=int, default=4, help="Monte Carlo runs per manifest row")
    p.add_argument("--threads", type=int, default=2, help="OpenMP threads")
    p.add_argument("--base-values", default="1e-2,1", help="Comma-separated c values")
    p.add_argument("--schedules", default=ALL_SCHEDULES, help="Comma-separated schedules")
    p.add_argument("--projections", default=ALL_PROJECTIONS, help="Comma-separated projections")
    p.add_argument("--t0", default="0", help="t0 offset for applicable schedules")
    p.add_argument("--dense-prefix", type=int, default=20, help="Dense checkpoint prefix")
    p.add_argument("--log-step-decades", default="0.25", help="Log checkpoint stride")
    p.add_argument("--no-clean", action="store_true", help="Do not remove work-root before running")
    p.add_argument("--keep", action="store_true", help="Keep generated outputs after success")
    p.add_argument("--plot-check", action="store_true", help="Also generate plots and embedded report for first candidate run")
    p.add_argument("--plot-python", default="", help="Python executable for plot check")
    return p.parse_args()


def split_csv(value: str) -> list[str]:
    return [x.strip() for x in value.split(",") if x.strip()]


def canonical_env_id(value: str) -> str:
    token = value.strip().lower().replace("-", "").replace("_", "").replace(" ", "")
    if token == "toyexample":
        return "toyexample"
    if token.startswith("e") and token[1:].isdigit():
        return f"E{int(token[1:])}"
    return value.strip()


def assert_safe_work_root(work_root: Path, repo_root: Path) -> None:
    resolved = work_root.resolve()
    home = Path.home().resolve()
    if resolved.name in REPO_DANGEROUS_NAMES:
        raise SystemExit(f"unsafe work-root: {resolved}")
    if resolved in {Path("/").resolve(), home, repo_root, repo_root.parent.resolve()}:
        raise SystemExit(f"refusing to clean dangerous work-root: {resolved}")


def run_cmd(cmd: list[str], cwd: Path, env: dict[str, str] | None = None) -> float:
    start = time.monotonic()
    print("[cmd]", " ".join(cmd), flush=True)
    subprocess.run(cmd, cwd=cwd, env=env, check=True)
    return time.monotonic() - start


def run_sweep(
    bin_path: Path,
    env_name: str,
    outdir: Path,
    args: argparse.Namespace,
    repo_root: Path,
) -> float:
    outdir.parent.mkdir(parents=True, exist_ok=True)
    cmd = [
        str(bin_path),
        "sweep",
        "--env",
        env_name,
        *ENV_EXTRA_ARGS.get(env_name, []),
        "--n_steps",
        str(args.n_steps),
        "--n_runs",
        str(args.n_runs),
        "--base_values",
        args.base_values,
        "--schedules",
        args.schedules,
        "--projections",
        args.projections,
        "--t0",
        str(args.t0),
        "--dense_prefix",
        str(args.dense_prefix),
        "--log_step_decades",
        str(args.log_step_decades),
        "--threads",
        str(args.threads),
        "--outdir",
        str(outdir),
        "--skip_plots",
    ]
    return run_cmd(cmd, cwd=repo_root)


def list_relative_files(root: Path) -> list[Path]:
    return sorted(p.relative_to(root) for p in root.rglob("*") if p.is_file())


def compare_dirs(env_name: str, baseline_dir: Path, candidate_dir: Path, tb: float, tc: float) -> CompareResult:
    baseline_files = list_relative_files(baseline_dir)
    candidate_files = set(list_relative_files(candidate_dir))

    diff_files = 0
    missing_files = 0
    for rel in baseline_files:
        b = baseline_dir / rel
        c = candidate_dir / rel
        if rel not in candidate_files:
            missing_files += 1
            print(f"[missing] env={env_name} candidate missing {rel}")
            continue
        if not filecmp.cmp(b, c, shallow=False):
            diff_files += 1
            print(f"[diff] env={env_name} {rel}")

    extra_files = sorted(candidate_files.difference(baseline_files))
    for rel in extra_files:
        missing_files += 1
        print(f"[extra] env={env_name} candidate extra {rel}")

    return CompareResult(
        env=env_name,
        total_files=len(baseline_files),
        diff_files=diff_files,
        missing_files=missing_files,
        elapsed_baseline_s=tb,
        elapsed_candidate_s=tc,
    )


def find_plot_python(repo_root: Path, explicit: str) -> str:
    if explicit:
        return explicit
    venv_py = repo_root / ".venv_plot" / "bin" / "python"
    if venv_py.exists():
        return str(venv_py)
    return sys.executable


def run_plot_check(repo_root: Path, run_dir: Path, args: argparse.Namespace) -> None:
    env = os.environ.copy()
    env.setdefault("UV_CACHE_DIR", "/tmp/uv-cache")
    env.setdefault("MPLCONFIGDIR", str(repo_root / ".mplconfig"))
    py = find_plot_python(repo_root, args.plot_python)
    report = run_dir / "report_v2_embedded.html"
    run_cmd([py, "scripts/plot_suite_v2.py", "--run-dir", str(run_dir)], cwd=repo_root, env=env)
    run_cmd(
        [py, "scripts/generate_embedded_report_v2.py", "--root", str(run_dir), "--out", str(report)],
        cwd=repo_root,
        env=env,
    )
    if not report.exists():
        raise RuntimeError(f"plot check did not produce {report}")


def write_summary(path: Path, results: list[CompareResult]) -> None:
    with path.open("w", encoding="utf-8") as f:
        f.write("env\ttotal_files\tdiff_files\tmissing_or_extra_files\tbaseline_seconds\tcandidate_seconds\tspeedup\n")
        for r in results:
            speedup = r.elapsed_baseline_s / r.elapsed_candidate_s if r.elapsed_candidate_s > 0 else float("inf")
            f.write(
                f"{r.env}\t{r.total_files}\t{r.diff_files}\t{r.missing_files}\t"
                f"{r.elapsed_baseline_s:.6f}\t{r.elapsed_candidate_s:.6f}\t{speedup:.6f}\n"
            )


def main() -> None:
    args = parse_args()
    repo_root = Path.cwd().resolve()
    baseline_bin = (repo_root / args.baseline_bin).resolve() if not Path(args.baseline_bin).is_absolute() else Path(args.baseline_bin)
    candidate_bin = (repo_root / args.candidate_bin).resolve() if not Path(args.candidate_bin).is_absolute() else Path(args.candidate_bin)
    work_root = Path(args.work_root).resolve()

    if not baseline_bin.exists():
        raise SystemExit(f"baseline binary not found: {baseline_bin}")
    if not candidate_bin.exists():
        raise SystemExit(f"candidate binary not found: {candidate_bin}")
    assert_safe_work_root(work_root, repo_root)
    if not args.no_clean and work_root.exists():
        shutil.rmtree(work_root)
    work_root.mkdir(parents=True, exist_ok=True)

    envs = [canonical_env_id(x) for x in split_csv(args.envs)]
    if not envs:
        raise SystemExit("--envs cannot be empty")

    results: list[CompareResult] = []
    first_candidate_dir: Path | None = None
    for env_name in envs:
        baseline_dir = work_root / "baseline" / f"{env_name}_gate"
        candidate_dir = work_root / "candidate" / f"{env_name}_gate"
        print(f"[gate] env={env_name} baseline_dir={baseline_dir} candidate_dir={candidate_dir}")
        tb = run_sweep(baseline_bin, env_name, baseline_dir, args, repo_root)
        tc = run_sweep(candidate_bin, env_name, candidate_dir, args, repo_root)
        result = compare_dirs(env_name, baseline_dir, candidate_dir, tb, tc)
        results.append(result)
        if first_candidate_dir is None:
            first_candidate_dir = candidate_dir

    summary_path = work_root / "exactness_gate_summary.tsv"
    write_summary(summary_path, results)

    if args.plot_check and first_candidate_dir is not None:
        run_plot_check(repo_root, first_candidate_dir, args)

    total_diff = sum(r.diff_files for r in results)
    total_missing = sum(r.missing_files for r in results)
    print(f"[gate] wrote {summary_path}")
    for r in results:
        speedup = r.elapsed_baseline_s / r.elapsed_candidate_s if r.elapsed_candidate_s > 0 else float("inf")
        print(
            f"[gate] {r.env}: files={r.total_files} diff={r.diff_files} "
            f"missing_or_extra={r.missing_files} speedup={speedup:.3f}x"
        )

    if total_diff or total_missing:
        raise SystemExit(f"exactness gate failed: diff={total_diff}, missing_or_extra={total_missing}")

    print("[gate] PASS: compared outputs are byte-identical")
    if not args.keep:
        print(f"[gate] removing {work_root}")
        shutil.rmtree(work_root)


if __name__ == "__main__":
    main()
