#!/usr/bin/env python3
"""Monitor progress for full C++ TD sweep runs."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Monitor full sweep progress from run root")
    p.add_argument("--root", required=True, help="Run root (contains env_* folders and launcher logs)")
    p.add_argument("--expected-envs", type=int, default=13, help="Expected number of environments")
    p.add_argument("--expected-c", type=int, default=17, help="Expected number of c/base values")
    p.add_argument("--expected-schedules", type=int, default=8, help="Expected number of schedules")
    p.add_argument("--expected-projections", type=int, default=3, help="Expected number of projections")
    return p.parse_args()


def manifest_rows(path: Path) -> int:
    with path.open("r", newline="", encoding="utf-8") as f:
        return sum(1 for _ in csv.DictReader(f, delimiter="\t"))


def main() -> None:
    args = parse_args()
    root = Path(args.root).resolve()
    expected_per_env = args.expected_c * args.expected_schedules * args.expected_projections
    expected_total = expected_per_env * args.expected_envs

    run_dirs = sorted(
        [
            p
            for p in root.iterdir()
            if p.is_dir() and ((p / "manifest.tsv").exists() or any(p.glob("agg_case_*.csv")))
        ]
    )
    env_lines: list[str] = []
    done_total = 0
    for rd in run_dirs:
        manifest = rd / "manifest.tsv"
        if manifest.exists():
            n_rows = manifest_rows(manifest)
            source = "manifest"
        else:
            n_rows = sum(1 for _ in rd.glob("agg_case_*.csv"))
            source = "agg-files"
        done_total += n_rows
        env = rd.name.split("_")[0]
        pct_env = 100.0 * n_rows / expected_per_env if expected_per_env > 0 else 0.0
        env_lines.append(
            f"{env}\trows={n_rows}/{expected_per_env}\tpct={pct_env:.2f}%\tsource={source}\trun_dir={rd.name}"
        )

    pct_total = 100.0 * done_total / expected_total if expected_total > 0 else 0.0
    print(f"root={root}")
    print(f"run_dirs={len(run_dirs)} expected_envs={args.expected_envs}")
    print(f"done_total={done_total} expected_total={expected_total} pct_total={pct_total:.4f}%")
    for line in env_lines:
        print(line)


if __name__ == "__main__":
    main()
