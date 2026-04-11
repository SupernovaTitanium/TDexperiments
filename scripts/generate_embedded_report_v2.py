#!/usr/bin/env python3
"""Generate a self-contained HTML report for v2 plots.

Supports variable numbers of environments/instances.
"""

from __future__ import annotations

import argparse
import base64
import csv
import html
import mimetypes
import re
from pathlib import Path

PREFERRED_ENV_ORDER = ["toyexample", "E1", "E2", "E3", "E4", "E5", "E6", "E7", "E8", "E9", "E10"]
PREFERRED_SCHEDULE_ORDER = ["theory", "theory_log2", "inv_t", "inv_sqrt_t", "inv_t_2_3", "inv_omega_t", "constant_omega", "constant"]
PREFERRED_PROJECTION_ORDER = ["none", "oracle", "upper"]


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Generate embedded HTML report for v2 plot suite")
    p.add_argument("--root", required=True, help="Run root (contains env run dirs and optional instance_structure_plots)")
    p.add_argument(
        "--summary-tsv",
        default="verification/summary_instance_44cases.tsv",
        help="TSV containing alpha/tau summary across instances",
    )
    p.add_argument("--out", default="", help="Output HTML path (default: <root>/report_v2_embedded.html)")
    return p.parse_args()


def image_data_uri(path: Path) -> str:
    mime = mimetypes.guess_type(str(path))[0] or "application/octet-stream"
    b64 = base64.b64encode(path.read_bytes()).decode("ascii")
    return f"data:{mime};base64,{b64}"


def env_sort_key(env: str) -> tuple[int, int, str]:
    if env in PREFERRED_ENV_ORDER:
        return (0, PREFERRED_ENV_ORDER.index(env), env)
    m = re.fullmatch(r"E(\d+)", env)
    if m:
        return (1, int(m.group(1)), env)
    return (2, 10**9, env)


def read_env_id_from_manifest(manifest: Path) -> str:
    with manifest.open("r", newline="", encoding="utf-8") as f:
        rd = csv.DictReader(f, delimiter="\t")
        row = next(rd, None)
    if row is None:
        return manifest.parent.name.split("_")[0]
    return row.get("env_id", manifest.parent.name.split("_")[0])


def find_run_dirs(root: Path) -> list[Path]:
    # If root itself is a run directory, use it directly.
    if (root / "manifest.tsv").exists():
        return [root]

    # Otherwise, pick latest run directory per env_id from children.
    candidates = [p for p in root.iterdir() if p.is_dir() and (p / "manifest.tsv").exists()]
    by_env: dict[str, list[Path]] = {}
    for rd in candidates:
        env = read_env_id_from_manifest(rd / "manifest.tsv")
        by_env.setdefault(env, []).append(rd)

    chosen: list[tuple[str, Path]] = []
    for env, arr in by_env.items():
        chosen.append((env, sorted(arr, key=lambda p: p.name)[-1]))

    chosen.sort(key=lambda t: env_sort_key(t[0]))
    return [p for _, p in chosen]


def method_sort_key(method: tuple[str, str]) -> tuple[int, int, str, str]:
    sched, proj = method
    sidx = PREFERRED_SCHEDULE_ORDER.index(sched) if sched in PREFERRED_SCHEDULE_ORDER else 999
    pidx = PREFERRED_PROJECTION_ORDER.index(proj) if proj in PREFERRED_PROJECTION_ORDER else 999
    return (sidx, pidx, sched, proj)


def collect_methods(run_dirs: list[Path]) -> list[tuple[str, str]]:
    methods: set[tuple[str, str]] = set()
    for rd in run_dirs:
        manifest = rd / "manifest.tsv"
        with manifest.open("r", newline="", encoding="utf-8") as f:
            rd_csv = csv.DictReader(f, delimiter="\t")
            for row in rd_csv:
                sched = (row.get("schedule", "") or "").strip()
                proj = (row.get("projection", "") or "").strip()
                if sched and proj:
                    methods.add((sched, proj))
    return sorted(methods, key=method_sort_key)


def schedule_definition(s: str) -> str:
    if s == "theory":
        return "alpha_t = 1 / (c * max(phi_infty^2,1e-12) * max(log(n_steps),1) * log(t+3) * sqrt(t+1))"
    if s == "theory_log2":
        return "alpha_t = 1 / (c * max(phi_infty^2,1e-12) * log(t+3)^2 * sqrt(t+1))"
    if s == "inv_t":
        return "alpha_t = 1 / (c * max(1, t + t0))"
    if s == "inv_sqrt_t":
        return "alpha_t = 1 / (c * sqrt(max(1, t + t0)))"
    if s == "inv_t_2_3":
        return "alpha_t = 1 / (c * max(1, t + t0)^(2/3))"
    if s == "inv_omega_t":
        return "alpha_t = 1 / (c * max(omega,1e-12) * max(1, t + t0))"
    if s == "constant_omega":
        return "alpha_t = max(omega,1e-12) / c"
    if s == "constant":
        return "alpha_t = 1 / c"
    return "alpha_t = (see schedule implementation)"


def projection_definition(p: str) -> tuple[str, str]:
    if p == "none":
        return ("No", "R = inf (no projection)")
    if p == "oracle":
        return ("Yes", "R = ||theta*||_2")
    if p == "upper":
        return ("Yes", "R = 2*r_max / (sqrt(omega) * (1-gamma)^(3/2))")
    return ("Unknown", "Unknown")


def plot_rank(name: str) -> tuple[int, str]:
    if "__bestcurves_by_c__metric-D__" in name:
        return (10, name)
    if "__bestcurves_by_c__metric-DA__" in name:
        return (20, name)
    if "__methods-bestc__metric-D" in name:
        return (30, name)
    if "__methods-bestc__metric-DA" in name:
        return (40, name)
    if "__algo-finalgrid__" in name:
        return (50, name)
    if "__algo-curves-by-c__metric-D__" in name:
        return (60, name)
    if "__algo-curves-by-c__metric-DA__" in name:
        return (70, name)
    if "__omega_final_error_D__" in name:
        return (80, name)
    if "__omega_final_error_DA__" in name:
        return (90, name)
    return (999, name)


def read_alpha_table(tsv_path: Path) -> list[dict[str, str]]:
    if not tsv_path.exists():
        return []
    rows: list[dict[str, str]] = []
    with tsv_path.open("r", newline="", encoding="utf-8") as f:
        rd = csv.DictReader(f, delimiter="\t")
        for row in rd:
            rows.append(row)

    def key(r: dict[str, str]) -> tuple[tuple[int, int, str], int, float]:
        env = r.get("env", "")
        case_id = r.get("case_id", "0")
        control_value = r.get("control_value", "nan")
        try:
            c = int(case_id)
        except Exception:
            c = 0
        try:
            v = float(control_value)
        except Exception:
            v = float("inf")
        return (env_sort_key(env), c, v)

    rows.sort(key=key)
    return rows


def fnum(x: str, fmt: str = ".6g") -> str:
    try:
        v = float(x)
    except Exception:
        return html.escape(str(x))
    return format(v, fmt)


def build_html(
    root: Path,
    run_dirs: list[Path],
    methods: list[tuple[str, str]],
    alpha_rows: list[dict[str, str]],
    structure_dir: Path,
    summary_path: Path,
) -> str:
    toc = []
    sections = []
    total_embedded = 0

    if methods:
        toc.append("<a href='#algo-defs'>algorithm_definitions</a>")

    for rd in run_dirs:
        env = read_env_id_from_manifest(rd / "manifest.tsv")
        toc.append(f"<a href='#{html.escape(rd.name)}'>{html.escape(env)}</a>")
        plot_dir = rd / "plots"
        pngs = sorted(plot_dir.glob("*.png"), key=lambda p: plot_rank(p.name))
        total_embedded += len(pngs)

        cards: list[str] = []
        for p in pngs:
            cards.append(
                "<figure>"
                f"<img loading='lazy' src='{html.escape(image_data_uri(p))}' alt='{html.escape(p.name)}'>"
                f"<figcaption>{html.escape(p.name)}</figcaption>"
                "</figure>"
            )

        sections.append(
            f"<section id='{html.escape(rd.name)}'>"
            f"<h2>{html.escape(env)} ({html.escape(rd.name)})</h2>"
            f"<p class='meta'>plots: {len(pngs)} PNG</p>"
            f"<div class='grid'>{''.join(cards)}</div>"
            "</section>"
        )

    algo_defs_html = ""
    if methods:
        lines = [
            "<section id='algo-defs'>",
            "<h2>Algorithm Definitions (Schedules + Projection Variants)</h2>",
            "<p class='meta'>Methods are read from manifest.tsv in this run root.</p>",
            "<table><thead><tr><th>method</th><th>stepsize_schedule</th><th>stepsize_definition</th><th>projection</th><th>projected?</th><th>projection_radius</th></tr></thead><tbody>",
        ]
        for sched, proj in methods:
            projected, radius = projection_definition(proj)
            method_id = f"project:{proj},stepsize:{sched}"
            lines.append(
                "<tr>"
                f"<td>{html.escape(method_id)}</td>"
                f"<td>{html.escape(sched)}</td>"
                f"<td><code>{html.escape(schedule_definition(sched))}</code></td>"
                f"<td>{html.escape(proj)}</td>"
                f"<td>{html.escape(projected)}</td>"
                f"<td><code>{html.escape(radius)}</code></td>"
                "</tr>"
            )
        lines.append("</tbody></table></section>")
        algo_defs_html = "".join(lines)

    alpha_table_html = ""
    if alpha_rows:
        lines = [
            "<section id='alpha-table'>",
            "<h2>TD Instances Table: 1/(1-α) (tau_alpha)</h2>",
            f"<p class='meta'>source: {html.escape(str(summary_path))}</p>",
            "<table><thead><tr>"
            "<th>env</th><th>case_id</th><th>control_key</th><th>control_value</th>"
            "<th>omega</th><th>lambda_min((A+A^T)/2)</th><th>alpha_hat</th><th>1/(1-α)</th>"
            "</tr></thead><tbody>",
        ]
        for r in alpha_rows:
            lines.append(
                "<tr>"
                f"<td>{html.escape(r.get('env', ''))}</td>"
                f"<td>{html.escape(r.get('case_id', ''))}</td>"
                f"<td>{html.escape(r.get('control_key', ''))}</td>"
                f"<td>{fnum(r.get('control_value', ''))}</td>"
                f"<td>{fnum(r.get('omega', ''))}</td>"
                f"<td>{fnum(r.get('lambda_min_A_plus_AT_over_2', r.get('lambda_min_A_plus_AT', '')))}</td>"
                f"<td>{fnum(r.get('alpha_hat', ''))}</td>"
                f"<td>{fnum(r.get('tau_alpha', ''))}</td>"
                "</tr>"
            )
        lines.append("</tbody></table></section>")
        alpha_table_html = "".join(lines)

    structure_html = ""
    if structure_dir.exists():
        pngs = sorted(structure_dir.glob("*.png"))
        total_embedded += len(pngs)
        cards = []
        for p in pngs:
            cards.append(
                "<figure>"
                f"<img loading='lazy' src='{html.escape(image_data_uri(p))}' alt='{html.escape(p.name)}'>"
                f"<figcaption>{html.escape(p.name)}</figcaption>"
                "</figure>"
            )
        structure_html = (
            "<section id='instance-structure'>"
            "<h2>Instance Structure Plots</h2>"
            f"<p class='meta'>directory: {html.escape(str(structure_dir))} | plots: {len(pngs)} PNG</p>"
            f"<div class='grid'>{''.join(cards)}</div>"
            "</section>"
        )
        toc.append("<a href='#instance-structure'>instance_structure_plots</a>")

    return f"""<!doctype html>
<html lang=\"en\">
<head>
  <meta charset=\"utf-8\">
  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
  <title>TD C++ v2 Embedded Report</title>
  <style>
    body {{ font-family: -apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif; margin: 22px; color: #222; }}
    h1 {{ margin: 0 0 4px 0; }}
    .sub {{ color: #555; margin: 0 0 10px 0; font-size: 13px; }}
    .toc a {{ margin-right: 10px; font-size: 13px; }}
    section {{ margin-top: 18px; }}
    .meta {{ color: #444; font-size: 12px; margin: 4px 0 8px 0; }}
    .grid {{ display: grid; grid-template-columns: repeat(auto-fill, minmax(270px, 1fr)); gap: 10px; }}
    figure {{ margin: 0; border: 1px solid #ddd; padding: 6px; background: #fff; }}
    figure img {{ width: 100%; height: auto; display: block; }}
    figcaption {{ font-size: 11px; color: #444; margin-top: 4px; word-break: break-all; }}
    table {{ border-collapse: collapse; width: 100%; font-size: 12px; margin-top: 8px; }}
    th, td {{ border: 1px solid #ddd; padding: 5px 7px; text-align: left; }}
    th {{ background: #f5f7f9; }}
    tr:nth-child(even) {{ background: #fafafa; }}
  </style>
</head>
<body>
  <h1>TD C++ v2 Embedded Report</h1>
  <p class=\"sub\">Root: {html.escape(str(root))}</p>
  <p class=\"sub\">Embedded PNG count: {total_embedded}</p>
  <div class=\"toc\">{''.join(toc)}</div>
  {algo_defs_html}
  {alpha_table_html}
  {''.join(sections)}
  {structure_html}
</body>
</html>
"""


def main() -> None:
    args = parse_args()
    root = Path(args.root).resolve()
    out = Path(args.out).resolve() if args.out else (root / "report_v2_embedded.html")

    run_dirs = find_run_dirs(root)
    if not run_dirs:
        raise SystemExit(f"No run directories found in {root}")

    summary_path = Path(args.summary_tsv).resolve()
    methods = collect_methods(run_dirs)
    alpha_rows = read_alpha_table(summary_path)
    structure_dir = root / "instance_structure_plots"

    html_text = build_html(root, run_dirs, methods, alpha_rows, structure_dir, summary_path)
    out.write_text(html_text, encoding="utf-8")
    print(f"[report-v2] wrote {out}")
    print(f"[report-v2] env sections={len(run_dirs)} alpha_rows={len(alpha_rows)}")


if __name__ == "__main__":
    main()
