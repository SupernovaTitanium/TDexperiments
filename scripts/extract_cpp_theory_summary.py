#!/usr/bin/env python3
"""Extract compact theory summary from C++ run root (multiple env_* dirs)."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Extract C++ summary table from run directories")
    p.add_argument("--root", required=True, help="Root directory containing env run dirs")
    p.add_argument("--out", required=True, help="Output TSV path")
    return p.parse_args()


def read_last_row(path: Path) -> dict[str, str]:
    last: dict[str, str] | None = None
    with path.open("r", newline="", encoding="utf-8") as f:
        rd = csv.DictReader(f)
        for row in rd:
            last = row
    if last is None:
        raise RuntimeError(f"No data rows in {path}")
    return last


def divergence_rate_from_runs(path: Path) -> float:
    total = 0
    div = 0
    with path.open("r", newline="", encoding="utf-8") as f:
        rd = csv.DictReader(f)
        for row in rd:
            total += 1
            div += int(row.get("diverged", "0") or "0")
    return (div / total) if total > 0 else float("nan")


def main() -> None:
    args = parse_args()
    root = Path(args.root).resolve()
    out = Path(args.out).resolve()
    out.parent.mkdir(parents=True, exist_ok=True)

    rows_out: list[dict[str, str]] = []

    for run_dir in sorted([p for p in root.iterdir() if p.is_dir()]):
        manifest = run_dir / "manifest.tsv"
        if not manifest.exists():
            continue

        with manifest.open("r", newline="", encoding="utf-8") as f:
            rd = csv.DictReader(f, delimiter="\t")
            for row in rd:
                agg_path = run_dir / row["agg_file"]
                run_path = run_dir / row["run_file"]
                if not agg_path.exists() or not run_path.exists():
                    continue

                last = read_last_row(agg_path)
                div_rate = divergence_rate_from_runs(run_path)

                rows_out.append(
                    {
                        "env_id": row["env_id"],
                        "c": row["param_value"],
                        "omega": row["omega"],
                        "kappa": row["kappa"],
                        "final_D": last.get("E_D[||Vbar_t - V*||^2]", "nan"),
                        "final_A": last.get("E_A[||Vbar_t - V*||^2]", "nan"),
                        "divergence_rate": f"{div_rate:.12g}",
                    }
                )

    with out.open("w", newline="", encoding="utf-8") as f:
        fieldnames = ["env_id", "c", "omega", "kappa", "final_D", "final_A", "divergence_rate"]
        wr = csv.DictWriter(f, fieldnames=fieldnames, delimiter="\t")
        wr.writeheader()
        for row in sorted(rows_out, key=lambda r: (r["env_id"], float(r["c"]))):
            wr.writerow(row)

    print(f"[extract] wrote {len(rows_out)} rows to {out}")


if __name__ == "__main__":
    main()
