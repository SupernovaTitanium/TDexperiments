#!/usr/bin/env python3
"""Generate v2 TD plot suite per instance from manifest/agg/run CSV outputs.

This version supports variable numbers of omega-cases and methods.
"""

from __future__ import annotations

import argparse
import csv
import math
import re
from dataclasses import dataclass
from pathlib import Path

from matplotlib.lines import Line2D

try:
    import matplotlib.pyplot as plt
except ModuleNotFoundError as exc:
    raise SystemExit(
        "Missing dependency: matplotlib. Install with `python3 -m pip install matplotlib`."
    ) from exc


COL_T = "timestep"
COL_D = "E_D[||Vbar_t - V*||^2]"
COL_A = "E_A[||Vbar_t - V*||^2]"
COL_MAX_THETA = "max_i<=T ||theta_i||^2"
COL_THETA_STAR = "||theta^*||^2"

DEFAULT_SCHEDULE_ORDER = ["theory", "theory_log2", "inv_t", "inv_sqrt_t", "inv_t_2_3", "inv_omega_t", "constant_omega", "constant"]
DEFAULT_PROJECTION_ORDER = ["none", "oracle", "upper"]

SCHEDULE_COLORS = {
    "theory": "#0d3b66",
    "theory_log2": "#ff006e",
    "inv_t": "#f95738",
    "inv_sqrt_t": "#3a86ff",
    "inv_t_2_3": "#8ac926",
    "inv_omega_t": "#8338ec",
    "constant_omega": "#fb8500",
    "constant": "#2a9d8f",
}

PROJ_LINESTYLE = {
    "none": "-",
    "oracle": "--",
    "upper": ":",
}

EPS = 1e-16
Y_MIN_LOG = 1e-16
Y_MAX_LOG = 1e20


@dataclass(frozen=True)
class Record:
    case_id: str
    case_label: str
    omega: float
    lambda_sym: float
    method: tuple[str, str]  # (schedule, projection)
    c: float
    agg_path: Path
    run_path: Path


@dataclass(frozen=True)
class AggSummary:
    final_d: float
    final_a: float
    final_da: float
    ratio: float


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Generate v2 plot suite for one run directory")
    p.add_argument("--run-dir", required=True, help="Run directory containing manifest.tsv")
    p.add_argument("--out-dir", default="", help="Output directory (default: <run-dir>/plots)")
    p.add_argument("--max-points", type=int, default=2000, help="Max points per learning curve")
    p.add_argument("--no-clean", action="store_true", help="Do not delete existing png/eps in output directory")
    p.add_argument(
        "--max-cols",
        type=int,
        default=4,
        help="Max subplot columns for omega-grid figures (default: 4)",
    )
    return p.parse_args()


def read_manifest(path: Path) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    with path.open("r", newline="", encoding="utf-8") as f:
        rd = csv.DictReader(f, delimiter="\t")
        for row in rd:
            rows.append(row)
    return rows


def safe_float(x: str, default: float = math.nan) -> float:
    try:
        return float(x)
    except Exception:
        return default


def sanitize_slug(s: str) -> str:
    t = s.strip().lower()
    t = re.sub(r"[^a-z0-9._+-]+", "-", t)
    t = re.sub(r"-{2,}", "-", t).strip("-")
    return t or "na"


def method_id(method: tuple[str, str]) -> str:
    schedule, projection = method
    return f"stepsize-{sanitize_slug(schedule)}__proj-{sanitize_slug(projection)}"


def method_label(method: tuple[str, str]) -> str:
    schedule, projection = method
    return f"project:{projection},stepsize:{schedule}"


def omega_label(omega: float) -> str:
    return f"{omega:.3e}"


def lambda_label(x: float) -> str:
    return f"{x:.3e}"


def omega_lambda_title(omega: float, lambda_sym: float) -> str:
    return f"omega={omega_label(omega)}\nlambda_min((A+A^T)/2)={lambda_label(lambda_sym)}"


def omega_tag(omega: float) -> str:
    s = f"{omega:.3e}"
    s = s.replace("+", "p").replace("-", "m").replace(".", "d")
    return sanitize_slug(s)


def clean_output_dir(out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)
    for p in out_dir.glob("*"):
        if p.is_file() and p.suffix.lower() in {".png", ".eps"}:
            p.unlink()


def method_sort_key(method: tuple[str, str]) -> tuple[int, int, str, str]:
    s, p = method
    s_idx = DEFAULT_SCHEDULE_ORDER.index(s) if s in DEFAULT_SCHEDULE_ORDER else 999
    p_idx = DEFAULT_PROJECTION_ORDER.index(p) if p in DEFAULT_PROJECTION_ORDER else 999
    return (s_idx, p_idx, s, p)


def collect_records(
    run_dir: Path,
) -> tuple[str, list[str], list[float], list[tuple[str, str]], dict[tuple[str, tuple[str, str], float], Record]]:
    manifest = run_dir / "manifest.tsv"
    rows = read_manifest(manifest)
    if not rows:
        raise SystemExit(f"manifest is empty: {manifest}")

    env_name = rows[0].get("env_id", run_dir.name.split("_")[0])
    case_to_omega: dict[str, float] = {}
    case_to_label: dict[str, str] = {}
    c_values: set[float] = set()
    methods: set[tuple[str, str]] = set()
    out: dict[tuple[str, tuple[str, str], float], Record] = {}

    for row in rows:
        case_id = row.get("case_id", "")
        schedule = row.get("schedule", "")
        projection = row.get("projection", "")
        method = (schedule, projection)
        c = safe_float(row.get("param_value", "nan"))
        omega = safe_float(row.get("omega", "nan"))
        lambda_sym = safe_float(row.get("lambda_sym", row.get("lambda_min_A_plus_AT", "nan")))
        if not (case_id and math.isfinite(c)):
            continue

        methods.add(method)
        case_to_omega[case_id] = omega
        case_to_label[case_id] = row.get("case_label", f"case {case_id}")
        c_values.add(c)
        out[(case_id, method, c)] = Record(
            case_id=case_id,
            case_label=case_to_label[case_id],
            omega=omega,
            lambda_sym=lambda_sym,
            method=method,
            c=c,
            agg_path=(run_dir / row["agg_file"]).resolve(),
            run_path=(run_dir / row["run_file"]).resolve(),
        )

    ordered_cases = sorted(case_to_omega.keys(), key=lambda cid: (case_to_omega[cid], cid))
    ordered_c = sorted(c_values)
    ordered_methods = sorted(methods, key=method_sort_key)

    return env_name, ordered_cases, ordered_c, ordered_methods, out


_summary_cache: dict[Path, AggSummary] = {}
_curve_cache: dict[tuple[Path, str, int], tuple[list[float], list[float]]] = {}
_div_cache: dict[Path, float] = {}


def read_agg_summary(path: Path) -> AggSummary:
    got = _summary_cache.get(path)
    if got is not None:
        return got
    if not path.exists():
        out = AggSummary(math.nan, math.nan, math.nan, math.nan)
        _summary_cache[path] = out
        return out

    final_d = math.nan
    final_a = math.nan
    ratio = math.nan
    with path.open("r", newline="", encoding="utf-8") as f:
        rd = csv.DictReader(f)
        for row in rd:
            d = safe_float(row.get(COL_D, "nan"))
            a = safe_float(row.get(COL_A, "nan"))
            if math.isfinite(d):
                final_d = d
            if math.isfinite(a):
                final_a = a
            max_theta = safe_float(row.get(COL_MAX_THETA, "nan"))
            theta_star_sq = safe_float(row.get(COL_THETA_STAR, "nan"))
            if math.isfinite(max_theta) and math.isfinite(theta_star_sq):
                ratio = max_theta / max(theta_star_sq, EPS)

    final_da = final_d + final_a if (math.isfinite(final_d) and math.isfinite(final_a)) else math.nan
    out = AggSummary(final_d=final_d, final_a=final_a, final_da=final_da, ratio=ratio)
    _summary_cache[path] = out
    return out


def read_curve(path: Path, metric: str, max_points: int) -> tuple[list[float], list[float]]:
    key = (path, metric, max_points)
    got = _curve_cache.get(key)
    if got is not None:
        return got
    if not path.exists():
        _curve_cache[key] = ([], [])
        return ([], [])

    xs: list[float] = []
    ys: list[float] = []
    with path.open("r", newline="", encoding="utf-8") as f:
        rd = csv.DictReader(f)
        for row in rd:
            t = safe_float(row.get(COL_T, "nan"))
            d = safe_float(row.get(COL_D, "nan"))
            a = safe_float(row.get(COL_A, "nan"))
            if metric == "D":
                y = d
            elif metric == "DA":
                y = d + a if (math.isfinite(d) and math.isfinite(a)) else math.nan
            else:
                raise ValueError(f"unknown metric: {metric}")
            if not (math.isfinite(t) and math.isfinite(y)):
                continue
            if t < 0 or y <= 0:
                continue
            xs.append(t + 1.0)
            ys.append(y)

    if len(xs) > max_points and max_points > 0:
        stride = max(1, math.ceil(len(xs) / max_points))
        xs = xs[::stride]
        ys = ys[::stride]

    out = (xs, ys)
    _curve_cache[key] = out
    return out


def read_divergence_rate(path: Path) -> float:
    got = _div_cache.get(path)
    if got is not None:
        return got
    if not path.exists():
        _div_cache[path] = 0.0
        return 0.0

    total = 0
    div = 0
    with path.open("r", newline="", encoding="utf-8") as f:
        rd = csv.DictReader(f)
        for row in rd:
            total += 1
            try:
                div += int(row.get("diverged", "0") or "0")
            except Exception:
                pass

    rate = 0.0 if total == 0 else div / total
    _div_cache[path] = rate
    return rate


def get_record(
    records: dict[tuple[str, tuple[str, str], float], Record],
    case_id: str,
    method: tuple[str, str],
    c: float,
) -> Record | None:
    return records.get((case_id, method, c))


def choose_best_c(
    records: dict[tuple[str, tuple[str, str], float], Record],
    c_values: list[float],
    case_id: str,
    method: tuple[str, str],
    metric: str,
) -> tuple[float, Record] | None:
    best: tuple[float, Record] | None = None
    best_score = float("inf")

    for c in c_values:
        rec = get_record(records, case_id, method, c)
        if rec is None:
            continue
        s = read_agg_summary(rec.agg_path)
        score = s.final_d if metric == "D" else s.final_da
        if not (math.isfinite(score) and score > 0):
            continue
        if (score < best_score) or (math.isclose(score, best_score) and best is not None and c < best[0]):
            best_score = score
            best = (c, rec)

    return best


def mk_c_color_map(c_values: list[float]) -> dict[float, tuple[float, float, float, float]]:
    cmap = plt.get_cmap("viridis")
    n = max(1, len(c_values))
    return {c: cmap(i / max(1, n - 1)) for i, c in enumerate(c_values)}


def flatten_axes(axes_obj):
    if hasattr(axes_obj, "ravel"):
        return list(axes_obj.ravel())
    return [axes_obj]


def grid_shape(n: int, max_cols: int = 4) -> tuple[int, int]:
    if n <= 0:
        return (1, 1)
    ncols = min(max_cols, n)
    nrows = math.ceil(n / ncols)
    return (nrows, ncols)


def setup_loglog(ax, xlabel: str, ylabel: str) -> None:
    ax.set_xscale("log")
    ax.set_yscale("log")
    ax.set_xlabel(xlabel)
    ax.set_ylabel(ylabel)
    ax.set_ylim(Y_MIN_LOG, Y_MAX_LOG)
    ax.grid(True, which="both", alpha=0.25)


def plot_best_curves_by_c(
    env: str,
    case_order: list[str],
    methods: list[tuple[str, str]],
    records: dict[tuple[str, tuple[str, str], float], Record],
    c_values: list[float],
    out_dir: Path,
    max_points: int,
    max_cols: int,
    metric: str,
) -> Path:
    metric_tag = "D" if metric == "D" else "DA"
    ylabel = "suboptimality D" if metric == "D" else "suboptimality D+A"

    nrows, ncols = grid_shape(len(case_order), max_cols=max_cols)
    fig, axes = plt.subplots(nrows, ncols, figsize=(5.4 * ncols, 4.6 * nrows), dpi=150)
    axes_list = flatten_axes(axes)

    legend_lines = [
        Line2D(
            [0],
            [0],
            color=SCHEDULE_COLORS.get(schedule, "#444444"),
            linestyle=PROJ_LINESTYLE.get(projection, "-"),
            linewidth=1.8,
            label=method_label((schedule, projection)),
        )
        for schedule, projection in methods
    ]

    for i, case_id in enumerate(case_order):
        ax = axes_list[i]
        omega = math.nan
        lambda_sym = math.nan
        for method in methods:
            best = choose_best_c(records, c_values, case_id, method, metric=metric)
            if best is None:
                continue
            _, rec = best
            omega = rec.omega
            lambda_sym = rec.lambda_sym
            xs, ys = read_curve(rec.agg_path, metric=metric, max_points=max_points)
            if not xs:
                continue
            schedule, projection = method
            ax.plot(
                xs,
                ys,
                color=SCHEDULE_COLORS.get(schedule, "#444444"),
                linestyle=PROJ_LINESTYLE.get(projection, "-"),
                linewidth=1.6,
                alpha=0.95,
            )
        setup_loglog(ax, "time step t", ylabel)
        ax.set_title(omega_lambda_title(omega, lambda_sym))

    for j in range(len(case_order), len(axes_list)):
        axes_list[j].axis("off")

    fig.legend(
        handles=legend_lines,
        labels=[h.get_label() for h in legend_lines],
        loc="lower center",
        bbox_to_anchor=(0.5, 0.01),
        ncol=min(4, max(1, len(legend_lines))),
        fontsize=8,
        frameon=False,
    )
    fig.suptitle(f"{env} best curves by c ({metric_tag})", fontsize=12)
    fig.tight_layout(rect=[0, 0.08, 1, 0.95])
    out = out_dir / f"{env}__bestcurves_by_c__metric-{metric_tag}__omega-grid-{nrows}x{ncols}.png"
    fig.savefig(out)
    plt.close(fig)
    return out


def plot_algo_final_grid(
    env: str,
    case_order: list[str],
    records: dict[tuple[str, tuple[str, str], float], Record],
    c_values: list[float],
    out_dir: Path,
    method: tuple[str, str],
) -> Path:
    nrows = max(1, len(case_order))
    fig, axes = plt.subplots(nrows, 4, figsize=(22, 4.2 * nrows), dpi=140)
    axes_list = flatten_axes(axes)

    for r, case_id in enumerate(case_order):
        row_axes = axes_list[r * 4 : (r + 1) * 4]
        xs: list[float] = []
        ratio: list[float] = []
        div: list[float] = []
        dvals: list[float] = []
        davals: list[float] = []
        omega = math.nan
        lambda_sym = math.nan

        for c in c_values:
            rec = get_record(records, case_id, method, c)
            if rec is None:
                continue
            omega = rec.omega
            lambda_sym = rec.lambda_sym
            s = read_agg_summary(rec.agg_path)
            xs.append(c)
            ratio.append(s.ratio if (math.isfinite(s.ratio) and s.ratio > 0) else Y_MAX_LOG)
            div.append(read_divergence_rate(rec.run_path))
            dvals.append(s.final_d if (math.isfinite(s.final_d) and s.final_d > 0) else EPS)
            davals.append(s.final_da if (math.isfinite(s.final_da) and s.final_da > 0) else EPS)

        ax = row_axes[0]
        ax.plot(xs, ratio, marker="o", linewidth=1.6)
        ax.set_xscale("log")
        ax.set_yscale("log")
        ax.set_ylim(Y_MIN_LOG, Y_MAX_LOG)
        ax.set_xlabel("c")
        ax.set_ylabel(f"{omega_lambda_title(omega, lambda_sym)}\nRatio")
        ax.grid(True, which="both", alpha=0.25)
        if r == 0:
            ax.set_title("Ratio vs c")

        ax = row_axes[1]
        ax.plot(xs, div, marker="o", linewidth=1.6, color="#e63946")
        ax.set_xscale("log")
        ax.set_xlabel("c")
        ax.set_ylabel("Divergence")
        ax.set_ylim(-0.03, 1.03)
        ax.grid(True, which="both", alpha=0.25)
        if r == 0:
            ax.set_title("Divergence vs c")

        ax = row_axes[2]
        ax.plot(xs, dvals, marker="o", linewidth=1.6, color="#3a86ff")
        ax.set_xscale("log")
        ax.set_yscale("log")
        ax.set_ylim(Y_MIN_LOG, Y_MAX_LOG)
        ax.set_xlabel("c")
        ax.set_ylabel("Final D")
        ax.grid(True, which="both", alpha=0.25)
        if r == 0:
            ax.set_title("Suboptimality D vs c")

        ax = row_axes[3]
        ax.plot(xs, davals, marker="o", linewidth=1.6, color="#8338ec")
        ax.set_xscale("log")
        ax.set_yscale("log")
        ax.set_ylim(Y_MIN_LOG, Y_MAX_LOG)
        ax.set_xlabel("c")
        ax.set_ylabel("Final D+A")
        ax.grid(True, which="both", alpha=0.25)
        if r == 0:
            ax.set_title("Suboptimality D+A vs c")

    fig.suptitle(f"{env} | {method_label(method)} | rows=omega, cols=ratio/div/D/DA", fontsize=12)
    fig.tight_layout(rect=[0, 0, 1, 0.96])
    out = out_dir / f"{env}__algo-finalgrid__method-{method_id(method)}__rows-omega__cols-ratio-div-D-DA.png"
    fig.savefig(out)
    plt.close(fig)
    return out


def plot_algo_curves_by_c(
    env: str,
    case_order: list[str],
    records: dict[tuple[str, tuple[str, str], float], Record],
    c_values: list[float],
    out_dir: Path,
    max_points: int,
    max_cols: int,
    method: tuple[str, str],
    metric: str,
) -> Path:
    metric_tag = "D" if metric == "D" else "DA"
    ylabel = "suboptimality D" if metric == "D" else "suboptimality D+A"

    nrows, ncols = grid_shape(len(case_order), max_cols=max_cols)
    fig, axes = plt.subplots(nrows, ncols, figsize=(5.0 * ncols, 4.2 * nrows), dpi=150)
    axes_list = flatten_axes(axes)
    c_map = mk_c_color_map(c_values)

    for i, case_id in enumerate(case_order):
        ax = axes_list[i]
        omega = math.nan
        lambda_sym = math.nan
        for c in c_values:
            rec = get_record(records, case_id, method, c)
            if rec is None:
                continue
            omega = rec.omega
            lambda_sym = rec.lambda_sym
            xs, ys = read_curve(rec.agg_path, metric=metric, max_points=max_points)
            if not xs:
                continue
            ax.plot(xs, ys, color=c_map[c], linewidth=1.4, label=f"c={c:.3g}")
        setup_loglog(ax, "time step t", ylabel)
        ax.set_title(omega_lambda_title(omega, lambda_sym))
        if i == 0:
            ax.legend(loc="best", fontsize=8, frameon=False)

    for j in range(len(case_order), len(axes_list)):
        axes_list[j].axis("off")

    fig.suptitle(f"{env} | {method_label(method)} | metric={metric_tag} | curves by c", fontsize=12)
    fig.tight_layout(rect=[0, 0, 1, 0.96])
    out = out_dir / f"{env}__algo-curves-by-c__metric-{metric_tag}__method-{method_id(method)}__omega-grid-{nrows}x{ncols}.png"
    fig.savefig(out)
    plt.close(fig)
    return out


def plot_methods_bestc_for_omega(
    env: str,
    case_order: list[str],
    methods: list[tuple[str, str]],
    records: dict[tuple[str, tuple[str, str], float], Record],
    c_values: list[float],
    out_dir: Path,
    max_points: int,
    metric: str,
) -> list[Path]:
    metric_tag = "D" if metric == "D" else "DA"
    ylabel = "suboptimality D" if metric == "D" else "suboptimality D+A"
    out_paths: list[Path] = []

    for idx, case_id in enumerate(case_order, start=1):
        fig, ax = plt.subplots(figsize=(11, 7), dpi=150)
        omega = math.nan
        lambda_sym = math.nan
        plotted = 0
        for method in methods:
            best = choose_best_c(records, c_values, case_id, method, metric=metric)
            if best is None:
                continue
            c_star, rec = best
            omega = rec.omega
            lambda_sym = rec.lambda_sym
            xs, ys = read_curve(rec.agg_path, metric=metric, max_points=max_points)
            if not xs:
                continue
            schedule, projection = method
            ax.plot(
                xs,
                ys,
                color=SCHEDULE_COLORS.get(schedule, "#444444"),
                linestyle=PROJ_LINESTYLE.get(projection, "-"),
                linewidth=1.5,
                label=f"{method_label(method)},best_c={c_star:.3g}",
            )
            plotted += 1

        if plotted == 0:
            plt.close(fig)
            continue

        setup_loglog(ax, "time step t", ylabel)
        ax.set_title(f"{env} | {omega_lambda_title(omega, lambda_sym)} | methods(best c) | metric={metric_tag}")
        ax.legend(loc="best", fontsize=7, frameon=False)
        fig.tight_layout()
        out = out_dir / f"{env}__omega-{idx:02d}-{omega_tag(omega)}__methods-bestc__metric-{metric_tag}.png"
        fig.savefig(out)
        plt.close(fig)
        out_paths.append(out)

    return out_paths


def plot_omega_final_error_per_method(
    env: str,
    case_order: list[str],
    records: dict[tuple[str, tuple[str, str], float], Record],
    c_values: list[float],
    out_dir: Path,
    method: tuple[str, str],
    metric: str,
) -> Path:
    metric_tag = "D" if metric == "D" else "DA"
    ylabel = "final suboptimality D" if metric == "D" else "final suboptimality D+A"
    c_map = mk_c_color_map(c_values)
    fig, ax = plt.subplots(figsize=(8, 6), dpi=150)

    for c in c_values:
        xs: list[float] = []
        ys: list[float] = []
        for case_id in case_order:
            rec = get_record(records, case_id, method, c)
            if rec is None:
                continue
            s = read_agg_summary(rec.agg_path)
            y = s.final_d if metric == "D" else s.final_da
            if not (math.isfinite(rec.omega) and math.isfinite(y)):
                continue
            if rec.omega <= 0 or y <= 0:
                continue
            xs.append(rec.omega)
            ys.append(y)
        if xs:
            ax.scatter(xs, ys, s=34, alpha=0.85, color=c_map[c], label=f"c={c:.3g}")

    setup_loglog(ax, "omega level", ylabel)
    ax.set_title(f"{env} | {method_label(method)} | omega-final-error ({metric_tag})")
    ax.legend(loc="best", fontsize=8, frameon=False)
    fig.tight_layout()
    out = out_dir / f"{env}__omega_final_error_{metric_tag}__method-{method_id(method)}.png"
    fig.savefig(out)
    plt.close(fig)
    return out


def write_inventory(paths: list[Path], out_dir: Path) -> None:
    out = out_dir / "plot_inventory_v2.tsv"
    with out.open("w", newline="", encoding="utf-8") as f:
        wr = csv.writer(f, delimiter="\t")
        wr.writerow(["filename"])
        for p in sorted(paths, key=lambda z: z.name):
            wr.writerow([p.name])


def main() -> None:
    args = parse_args()
    run_dir = Path(args.run_dir).resolve()
    manifest = run_dir / "manifest.tsv"
    if not manifest.exists():
        raise SystemExit(f"manifest.tsv not found in {run_dir}")

    out_dir = Path(args.out_dir).resolve() if args.out_dir else run_dir / "plots"
    out_dir.mkdir(parents=True, exist_ok=True)
    if not args.no_clean:
        clean_output_dir(out_dir)

    env, case_order, c_values, methods, records = collect_records(run_dir)
    if len(case_order) == 0:
        raise SystemExit(f"no cases found in {run_dir}")

    created: list[Path] = []

    # 1 + 1.5
    created.append(
        plot_best_curves_by_c(
            env, case_order, methods, records, c_values, out_dir, args.max_points, args.max_cols, metric="D"
        )
    )
    created.append(
        plot_best_curves_by_c(
            env, case_order, methods, records, c_values, out_dir, args.max_points, args.max_cols, metric="DA"
        )
    )

    # 2 + 3 + 4 + 7 + 8
    for method in methods:
        created.append(plot_algo_final_grid(env, case_order, records, c_values, out_dir, method))
        created.append(
            plot_algo_curves_by_c(
                env,
                case_order,
                records,
                c_values,
                out_dir,
                args.max_points,
                args.max_cols,
                method,
                metric="D",
            )
        )
        created.append(
            plot_algo_curves_by_c(
                env,
                case_order,
                records,
                c_values,
                out_dir,
                args.max_points,
                args.max_cols,
                method,
                metric="DA",
            )
        )
        created.append(plot_omega_final_error_per_method(env, case_order, records, c_values, out_dir, method, metric="D"))
        created.append(plot_omega_final_error_per_method(env, case_order, records, c_values, out_dir, method, metric="DA"))

    # 5 + 6
    created.extend(plot_methods_bestc_for_omega(env, case_order, methods, records, c_values, out_dir, args.max_points, metric="D"))
    created.extend(plot_methods_bestc_for_omega(env, case_order, methods, records, c_values, out_dir, args.max_points, metric="DA"))

    write_inventory(created, out_dir)
    print(f"[v2] env={env} cases={len(case_order)} c={len(c_values)} methods={len(methods)}")
    print(f"[v2] wrote {len(created)} png files to {out_dir}")


if __name__ == "__main__":
    main()
