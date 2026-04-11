#!/usr/bin/env python3
"""Compare compact theory summaries from C++ and Julia."""

from __future__ import annotations

import argparse
import csv
import math
from pathlib import Path


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Compare C++ and Julia summary TSV files")
    p.add_argument("--cpp", required=True, help="C++ summary TSV")
    p.add_argument("--julia", required=True, help="Julia summary TSV")
    p.add_argument("--out", required=True, help="Output TSV with comparison metrics")
    return p.parse_args()


def read_table(path: Path) -> list[dict[str, str]]:
    with path.open("r", newline="", encoding="utf-8") as f:
        rd = csv.DictReader(f, delimiter="\t")
        return list(rd)


def key(row: dict[str, str]) -> tuple[str, str]:
    return (row["env_id"], f"{float(row['c']):.12g}")


def rel_err(a: float, b: float) -> float:
    if not (math.isfinite(a) and math.isfinite(b)):
        return float("nan")
    return abs(a - b) / max(1e-30, abs(b))


def main() -> None:
    args = parse_args()
    cpp_rows = read_table(Path(args.cpp).resolve())
    julia_rows = read_table(Path(args.julia).resolve())

    cpp_map = {key(r): r for r in cpp_rows}
    julia_map = {key(r): r for r in julia_rows}

    keys = sorted(set(cpp_map).intersection(julia_map))

    out_path = Path(args.out).resolve()
    out_path.parent.mkdir(parents=True, exist_ok=True)

    stats = {
        "omega_rel_max": 0.0,
        "kappa_rel_max": 0.0,
        "finalD_rel_max": 0.0,
        "finalA_rel_max": 0.0,
        "div_abs_max": 0.0,
    }

    with out_path.open("w", newline="", encoding="utf-8") as f:
        fieldnames = [
            "env_id",
            "c",
            "omega_cpp",
            "omega_julia",
            "omega_rel_err",
            "kappa_cpp",
            "kappa_julia",
            "kappa_rel_err",
            "final_D_cpp",
            "final_D_julia",
            "final_D_rel_err",
            "final_A_cpp",
            "final_A_julia",
            "final_A_rel_err",
            "div_cpp",
            "div_julia",
            "div_abs_err",
        ]
        wr = csv.DictWriter(f, fieldnames=fieldnames, delimiter="\t")
        wr.writeheader()

        for k in keys:
            c = cpp_map[k]
            j = julia_map[k]

            omega_cpp = float(c["omega"])
            omega_j = float(j["omega"])
            kappa_cpp = float(c["kappa"])
            kappa_j = float(j["kappa"])
            d_cpp = float(c["final_D"])
            d_j = float(j["final_D"])
            a_cpp = float(c["final_A"])
            a_j = float(j["final_A"])
            div_cpp = float(c["divergence_rate"])
            div_j = float(j["divergence_rate"])

            row = {
                "env_id": k[0],
                "c": k[1],
                "omega_cpp": f"{omega_cpp:.12g}",
                "omega_julia": f"{omega_j:.12g}",
                "omega_rel_err": f"{rel_err(omega_cpp, omega_j):.12g}",
                "kappa_cpp": f"{kappa_cpp:.12g}",
                "kappa_julia": f"{kappa_j:.12g}",
                "kappa_rel_err": f"{rel_err(kappa_cpp, kappa_j):.12g}",
                "final_D_cpp": f"{d_cpp:.12g}",
                "final_D_julia": f"{d_j:.12g}",
                "final_D_rel_err": f"{rel_err(d_cpp, d_j):.12g}",
                "final_A_cpp": f"{a_cpp:.12g}",
                "final_A_julia": f"{a_j:.12g}",
                "final_A_rel_err": f"{rel_err(a_cpp, a_j):.12g}",
                "div_cpp": f"{div_cpp:.12g}",
                "div_julia": f"{div_j:.12g}",
                "div_abs_err": f"{abs(div_cpp - div_j):.12g}",
            }
            wr.writerow(row)

            stats["omega_rel_max"] = max(stats["omega_rel_max"], rel_err(omega_cpp, omega_j))
            stats["kappa_rel_max"] = max(stats["kappa_rel_max"], rel_err(kappa_cpp, kappa_j))
            stats["finalD_rel_max"] = max(stats["finalD_rel_max"], rel_err(d_cpp, d_j))
            stats["finalA_rel_max"] = max(stats["finalA_rel_max"], rel_err(a_cpp, a_j))
            stats["div_abs_max"] = max(stats["div_abs_max"], abs(div_cpp - div_j))

    print(f"[compare] matched rows: {len(keys)}")
    print("[compare] maxima:")
    for k, v in stats.items():
        print(f"  {k}={v:.12g}")
    print(f"[compare] wrote {out_path}")


if __name__ == "__main__":
    main()
