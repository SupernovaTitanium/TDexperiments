#!/usr/bin/env python3
"""Generate detailed summary_instance.md for renumbered TD instances (no numpy dependency)."""

from __future__ import annotations

import argparse
import csv
import math
import subprocess
from dataclasses import dataclass
from pathlib import Path

ENV_ORDER = [
    "toyexample",
    "E1",
    "E2",
    "E3",
    "E4",
    "E5",
    "E6",
    "E7",
    "E8",
    "E9",
    "E10",
]

# New numbering after removing legacy E3 and E7:
# new E3<-old E4, E4<-old E5, E5<-old E6, E6<-old E8, E7<-old E9,
# E8<-old E10, E9<-old E11, E10<-old E12.
SOURCE_ENV = {
    "toyexample": "toyexample",
    "E1": "E1",
    "E2": "E2",
    "E3": "E4",
    "E4": "E5",
    "E5": "E6",
    "E6": "E8",
    "E7": "E9",
    "E8": "E10",
    "E9": "E11",
    "E10": "E12",
}

DEFAULT_PARAMS = {
    "toyexample": {"gamma": "0.99", "seed": "114514", "scale_factor": "1.0", "feature_omega_beta": "1.0"},
    "E1": {"gamma": "0.99", "eps1": "1e-3", "eps2": "1e-2", "reward_mode": "zero", "rho": "1.0"},
    "E2": {"gamma": "0.99", "eps1": "1e-3", "eps2": "1e-2", "reward_mode": "zero", "rho": "1.0"},
    # old E4
    "E3": {"gamma": "0.99", "eps1": "1e-3", "eps2": "1e-2", "feature_omega_beta": "1.0", "reward_mode": "zero", "rho": "1.0"},
    # old E5
    "E4": {"gamma": "0.99", "m": "20", "eps1": "1e-2", "feature_omega_beta": "1.0", "reward_mode": "zero", "rho": "1.0"},
    # old E6
    "E5": {"gamma": "0.99", "m": "20", "eps1": "1e-2", "feature_omega_beta": "1.0", "reward_mode": "zero", "rho": "1.0"},
    # old E8
    "E6": {"gamma": "0.99", "m": "32", "eps1": "1e-2", "feature_omega_beta": "1.0", "reward_mode": "zero", "rho": "1.0"},
    # old E9
    "E7": {
        "gamma": "0.99",
        "m": "64",
        "eps1": "1e-2",
        "alpha_max": "1.5707963267948966",
        "feature_omega_beta": "1.0",
        "reward_mode": "zero",
        "rho": "1.0",
    },
    # old E10
    "E8": {"gamma": "0.99", "eps1": "1e-2", "eps2": "1e-2", "feature_omega_beta": "1.0", "reward_mode": "zero", "rho": "1.0"},
    # old E11
    "E9": {"gamma": "0.99", "m": "50", "eps2": "1e-2", "feature_omega_beta": "1.0", "reward_mode": "zero", "rho": "1.0"},
    # old E12
    "E10": {
        "gamma": "0.99",
        "k": "10",
        "eps1": "1e-3",
        "eps2": "1e-2",
        "feature_omega_beta": "1.0",
        "reward_mode": "cluster-opposite",
        "rho": "1.0",
    },
}


@dataclass
class CaseRow:
    env: str
    case_id: str
    metadata: dict[str, str]
    omega: float
    kappa: float
    phi_max_sq: float
    tau_proxy: float
    gamma: float
    theta_star_norm: float
    r_max: float


@dataclass
class Instance:
    key: str
    env: str
    case_id: str
    control_key: str
    control_value: str
    gamma: float
    n: int
    d: int
    omega: float
    kappa: float
    lambda_min_A_plus_AT_over_2: float
    phi_max_sq: float
    tau_proxy: float
    theta_star_norm: float
    r_max: float
    R_oracle: float
    R_upper: float
    best_k: int
    delta_bestk: float
    alpha_hat: float
    tau_alpha: float
    C_hat: float
    t_mix_upper_alpha: float
    D: list[float]
    matrix_dir: Path


class SplitMix64:
    def __init__(self, seed: int):
        self.state = seed & 0xFFFFFFFFFFFFFFFF

    def next_u64(self) -> int:
        self.state = (self.state + 0x9E3779B97F4A7C15) & 0xFFFFFFFFFFFFFFFF
        z = self.state
        z = ((z ^ (z >> 30)) * 0xBF58476D1CE4E5B9) & 0xFFFFFFFFFFFFFFFF
        z = ((z ^ (z >> 27)) * 0x94D049BB133111EB) & 0xFFFFFFFFFFFFFFFF
        return (z ^ (z >> 31)) & 0xFFFFFFFFFFFFFFFF

    def next_unit(self) -> float:
        return float(self.next_u64() >> 11) * (2.0 ** -53)


def parse_metadata(s: str) -> dict[str, str]:
    out: dict[str, str] = {}
    for part in (s or "").split(";"):
        if "=" in part:
            k, v = part.split("=", 1)
            out[k] = v
    return out


def fmt(x: float, digits: int = 12) -> str:
    if math.isnan(x):
        return "nan"
    if not math.isfinite(x):
        return "inf" if x > 0 else "-inf"
    return f"{x:.{digits}g}"


def latest_manifest_per_env(base_root: Path) -> dict[str, Path]:
    latest: dict[str, tuple[str, Path]] = {}
    for p in base_root.glob("*_*/manifest.tsv"):
        d = p.parent.name
        env = d.split("_")[0]
        ts = "_".join(d.split("_")[1:])
        if env not in latest or ts > latest[env][0]:
            latest[env] = (ts, p)
    return {k: v[1] for k, v in latest.items()}


def load_case_rows(base_root: Path) -> list[CaseRow]:
    manifests = latest_manifest_per_env(base_root)
    out: list[CaseRow] = []
    for env in ENV_ORDER:
        src_env = env
        mpath = manifests.get(src_env)
        if mpath is None:
            src_env = SOURCE_ENV.get(env, env)
            mpath = manifests.get(src_env)
        if mpath is None:
            raise RuntimeError(f"Missing manifest for {env} (source {src_env})")
        with mpath.open("r", newline="", encoding="utf-8") as f:
            rd = csv.DictReader(f, delimiter="\t")
            for r in rd:
                out.append(
                    CaseRow(
                        env=env,
                        case_id=r["case_id"],
                        metadata=parse_metadata(r.get("metadata", "")),
                        omega=float(r["omega"]),
                        kappa=float(r["kappa"]),
                        phi_max_sq=float(r.get("phi_max_sq", "nan")),
                        tau_proxy=float(r["tau_proxy"]) if r["tau_proxy"] != "inf" else float("inf"),
                        gamma=float(r["gamma"]),
                        theta_star_norm=float(r["theta_star_norm"]),
                        r_max=float(r["r_max"]),
                    )
                )
    out.sort(key=lambda x: (ENV_ORDER.index(x.env), int(x.case_id)))
    return out


def method_grid_info(base_root: Path) -> tuple[int, int, int]:
    manifests = latest_manifest_per_env(base_root)
    methods: set[tuple[str, str]] = set()
    schedules: set[str] = set()
    projections: set[str] = set()
    for mpath in manifests.values():
        with mpath.open("r", newline="", encoding="utf-8") as f:
            rd = csv.DictReader(f, delimiter="\t")
            for r in rd:
                sched = (r.get("schedule") or "").strip()
                proj = (r.get("projection") or "").strip()
                if not sched or not proj:
                    continue
                methods.add((sched, proj))
                schedules.add(sched)
                projections.add(proj)
    return len(methods), len(schedules), len(projections)


def normalize_rows(P: list[list[float]]) -> list[list[float]]:
    out: list[list[float]] = []
    for row in P:
        s = sum(row)
        if s <= 0:
            raise RuntimeError("non-positive row sum")
        out.append([v / s for v in row])
    return out


def stationary_distribution(P: list[list[float]], tol: float = 1e-14, max_iter: int = 200000) -> list[float]:
    n = len(P)
    x = [1.0 / n] * n
    for _ in range(max_iter):
        xn = [0.0] * n
        for i in range(n):
            xi = x[i]
            row = P[i]
            for j in range(n):
                xn[j] += xi * row[j]
        s = sum(xn)
        if not math.isfinite(s) or s <= 0:
            break
        xn = [v / s for v in xn]
        diff = sum(abs(a - b) for a, b in zip(xn, x))
        x = xn
        if diff < tol:
            break
    return x


def jacobi_eigenvalues_symmetric(A: list[list[float]], max_iter: int = 10000, tol: float = 1e-12) -> list[float]:
    n = len(A)
    if n == 0:
        return []
    M = [row[:] for row in A]
    for _ in range(max_iter):
        p, q = 0, 1 if n > 1 else 0
        mx = 0.0
        for i in range(n):
            for j in range(i + 1, n):
                v = abs(M[i][j])
                if v > mx:
                    mx = v
                    p, q = i, j
        if mx < tol or n == 1:
            break

        app = M[p][p]
        aqq = M[q][q]
        apq = M[p][q]
        if abs(apq) < tol:
            continue

        tau = (aqq - app) / (2.0 * apq)
        t = 1.0 / (abs(tau) + math.sqrt(1.0 + tau * tau))
        if tau < 0.0:
            t = -t
        c = 1.0 / math.sqrt(1.0 + t * t)
        s = t * c

        for k in range(n):
            if k == p or k == q:
                continue
            aik = M[k][p]
            akq = M[k][q]
            M[k][p] = c * aik - s * akq
            M[p][k] = M[k][p]
            M[k][q] = s * aik + c * akq
            M[q][k] = M[k][q]

        M[p][p] = c * c * app - 2.0 * s * c * apq + s * s * aqq
        M[q][q] = s * s * app + 2.0 * s * c * apq + c * c * aqq
        M[p][q] = 0.0
        M[q][p] = 0.0

    return [M[i][i] for i in range(n)]


def compute_lambda_min_A_plus_AT_over_2(
    P: list[list[float]], Phi: list[list[float]], D: list[float], gamma: float
) -> float:
    n = len(P)
    d = len(Phi[0]) if Phi else 0
    if n == 0 or d == 0:
        return float("nan")

    # B = Diag(D) * (I - gamma * P)
    B = [[0.0 for _ in range(n)] for _ in range(n)]
    for s in range(n):
        ds = D[s]
        rowP = P[s]
        for t in range(n):
            B[s][t] = ds * ((1.0 if s == t else 0.0) - gamma * rowP[t])

    # tmp = B * Phi (n x d)
    tmp = [[0.0 for _ in range(d)] for _ in range(n)]
    for s in range(n):
        for j in range(d):
            acc = 0.0
            for t in range(n):
                acc += B[s][t] * Phi[t][j]
            tmp[s][j] = acc

    # A = Phi^T * tmp (d x d)
    A = [[0.0 for _ in range(d)] for _ in range(d)]
    for i in range(d):
        for j in range(d):
            acc = 0.0
            for s in range(n):
                acc += Phi[s][i] * tmp[s][j]
            A[i][j] = acc

    # Sym = (A + A^T) / 2
    Sym = [[0.5 * (A[i][j] + A[j][i]) for j in range(d)] for i in range(d)]
    eig = jacobi_eigenvalues_symmetric(Sym)
    return min(eig) if eig else float("nan")


def apply_feature_omega_beta(Phi: list[list[float]], beta: float) -> list[list[float]]:
    if len(Phi) == 0:
        return Phi
    d = len(Phi[0])
    if d <= 1:
        return [row[:] for row in Phi]
    if not (beta > 0 and math.isfinite(beta)):
        raise RuntimeError("feature_omega_beta must be positive finite")
    out: list[list[float]] = []
    for row in Phi:
        rr = row[:]
        for j in range(1, d):
            rr[j] *= beta
        out.append(rr)
    return out


def normalize_phi_infty_sq(Phi: list[list[float]]) -> list[list[float]]:
    mx = 0.0
    for row in Phi:
        s = sum(v * v for v in row)
        if s > mx:
            mx = s
    if not (mx > 0 and math.isfinite(mx)):
        raise RuntimeError("invalid Phi")
    scale = 1.0 / math.sqrt(mx)
    return [[v * scale for v in row] for row in Phi]


def alternate_transition(eps1: float) -> list[list[float]]:
    return [[eps1, 1.0 - eps1], [1.0 - eps1, eps1]]


def sticky_transition(eps1: float) -> list[list[float]]:
    return [[1.0 - eps1, eps1], [eps1, 1.0 - eps1]]


def ring_transition(m: int, eps1: float) -> list[list[float]]:
    P = [[0.0 for _ in range(m)] for _ in range(m)]
    for i in range(m):
        P[i][i] = eps1
        P[i][(i + 1) % m] = 1.0 - eps1
    return P


def conveyor_transition(m: int, eps1: float) -> list[list[float]]:
    n = m + 1
    P = [[0.0 for _ in range(n)] for _ in range(n)]
    P[0][0] = 1.0 - eps1
    P[0][1] = eps1
    for i in range(1, m):
        P[i][i + 1] = 1.0
    P[n - 1][0] = 1.0
    return P


def reflecting_corridor_transition(m: int) -> list[list[float]]:
    n = m + 1
    P = [[0.0 for _ in range(n)] for _ in range(n)]
    P[0][0] = 0.75
    P[0][1] = 0.25
    for i in range(1, m):
        P[i][i - 1] = 0.25
        P[i][i] = 0.50
        P[i][i + 1] = 0.25
    P[n - 1][n - 2] = 0.25
    P[n - 1][n - 1] = 0.75
    return P


def build_env(env: str, params: dict[str, str]) -> tuple[float, list[list[float]], list[list[float]]]:
    gamma = float(params["gamma"])
    if env == "toyexample":
        n, d = 50, 5
        seed = int(float(params.get("seed", "114514")))
        scale_factor = float(params.get("scale_factor", "1.0"))
        beta = float(params.get("feature_omega_beta", "1.0"))

        P = [[0.0 for _ in range(n)] for _ in range(n)]
        for i in range(n):
            P[i][i] = 0.1
            P[i][(i + 1) % n] = 0.6
            P[i][(i - 1 + n) % n] = 0.3

        frng = SplitMix64(seed)
        Phi = [[10.0 * frng.next_unit() for _ in range(d)] for _ in range(n)]
        if scale_factor <= 1.0:
            for i in range(n):
                Phi[i][0] *= scale_factor
        else:
            for i in range(n):
                for j in range(d):
                    Phi[i][j] *= scale_factor
        Phi = apply_feature_omega_beta(Phi, beta)

    elif env == "E1":
        eps1 = float(params.get("eps1", "1e-3"))
        eps2 = float(params.get("eps2", "1e-2"))
        P = alternate_transition(eps1)
        cphi = math.sqrt(1.0 + eps2 * eps2)
        Phi = [[eps2 / cphi], [1.0 / cphi]]

    elif env == "E2":
        eps1 = float(params.get("eps1", "1e-3"))
        eps2 = float(params.get("eps2", "1e-2"))
        beta = float(params.get("feature_omega_beta", "1.0"))
        P = sticky_transition(eps1)
        cphi = math.sqrt(2.0 + eps2 * eps2)
        Phi = [[1.0 / cphi, 0.0], [1.0 / cphi, eps2 / cphi]]
        Phi = apply_feature_omega_beta(Phi, beta)

    elif env == "E3":
        # new E3 <- old E4
        eps1 = float(params.get("eps1", "1e-3"))
        eps2 = float(params.get("eps2", "1e-2"))
        beta = float(params.get("feature_omega_beta", "1.0"))
        P = [[0.0, 1.0, 0.0], [1.0 - eps1, 0.0, eps1], [eps1, 0.0, 1.0 - eps1]]
        cphi = math.sqrt(2.0 + eps2 * eps2)
        Phi = [[1.0 / cphi, 0.0], [1.0 / cphi, eps2 / cphi], [0.0, 0.0]]
        Phi = apply_feature_omega_beta(Phi, beta)

    elif env == "E4":
        # new E4 <- old E5
        m = int(float(params.get("m", "20")))
        eps1 = float(params.get("eps1", "1e-2"))
        beta = float(params.get("feature_omega_beta", "1.0"))
        P = ring_transition(m, eps1)
        Phi = [[1.0 if i == j else 0.0 for j in range(m)] for i in range(m)]
        Phi = apply_feature_omega_beta(Phi, beta)

    elif env == "E5":
        # new E5 <- old E6
        m = int(float(params.get("m", "20")))
        eps1 = float(params.get("eps1", "1e-2"))
        beta = float(params.get("feature_omega_beta", "1.0"))
        P = conveyor_transition(m, eps1)
        n = m + 1
        Phi = [[0.0 for _ in range(m)] for _ in range(n)]
        for i in range(m):
            Phi[i + 1][i] = 1.0
        Phi = apply_feature_omega_beta(Phi, beta)

    elif env == "E6":
        # new E6 <- old E8
        m = int(float(params.get("m", "32")))
        eps1 = float(params.get("eps1", "1e-2"))
        beta = float(params.get("feature_omega_beta", "1.0"))
        P = ring_transition(m, eps1)
        Phi = []
        for i in range(m):
            a = 2.0 * math.pi * i / m
            Phi.append([math.cos(a) / math.sqrt(m), math.sin(a) / math.sqrt(m)])
        Phi = apply_feature_omega_beta(Phi, beta)

    elif env == "E7":
        # new E7 <- old E9
        m = int(float(params.get("m", "64")))
        eps1 = float(params.get("eps1", "1e-2"))
        alpha_max = float(params.get("alpha_max", str(math.pi / 2.0)))
        beta = float(params.get("feature_omega_beta", "1.0"))
        n = m + 1
        P = [[0.0 for _ in range(n)] for _ in range(n)]
        P[0][1] = 1.0
        for i in range(1, m):
            P[i][i + 1] = 1.0 - eps1
            P[i][0] = eps1
        P[n - 1][0] = 1.0
        Phi = [[0.0, 0.0] for _ in range(n)]
        for i in range(m):
            a = alpha_max * float(i + 1) / float(m)
            Phi[i + 1][0] = math.cos(a) / math.sqrt(m)
            Phi[i + 1][1] = math.sin(a) / math.sqrt(m)
        Phi = apply_feature_omega_beta(Phi, beta)

    elif env == "E8":
        # new E8 <- old E10
        eps1 = float(params.get("eps1", "1e-2"))
        eps2 = float(params.get("eps2", "1e-2"))
        beta = float(params.get("feature_omega_beta", "1.0"))
        P = ring_transition(4, eps1)
        s = 1.0 / math.sqrt(3.0)
        Phi = [[1.0 * s, 0.0], [1.0 * s, eps2 * s], [0.0, 1.0 * s], [-1.0 * s, eps2 * s]]
        Phi = apply_feature_omega_beta(Phi, beta)

    elif env == "E9":
        # new E9 <- old E11
        m = int(float(params.get("m", "50")))
        eps2 = float(params.get("eps2", "1e-2"))
        beta = float(params.get("feature_omega_beta", "1.0"))
        P = reflecting_corridor_transition(m)
        n = m + 1
        cphi = math.sqrt((m + 1.0) * (1.0 + eps2 * eps2))
        Phi = []
        for i in range(n):
            slope = eps2 * (2.0 * i - m) / m
            Phi.append([1.0 / cphi, slope / cphi])
        Phi = apply_feature_omega_beta(Phi, beta)

    elif env == "E10":
        # new E10 <- old E12
        k = int(float(params.get("k", "10")))
        eps1 = float(params.get("eps1", "1e-3"))
        eps2 = float(params.get("eps2", "1e-2"))
        beta = float(params.get("feature_omega_beta", "1.0"))
        n = 2 * k
        P = [[0.0 for _ in range(n)] for _ in range(n)]
        for i in range(k):
            for j in range(k):
                P[i][j] = (1.0 - eps1) / k
            for j in range(k, n):
                P[i][j] = eps1 / k
        for i in range(k, n):
            for j in range(k):
                P[i][j] = eps1 / k
            for j in range(k, n):
                P[i][j] = (1.0 - eps1) / k
        cphi = math.sqrt(2.0 * k)
        Phi = [[0.0, 0.0] for _ in range(n)]
        for i in range(k):
            Phi[i][0] = 1.0 / cphi
            Phi[i][1] = eps2 / cphi
        for i in range(k, n):
            Phi[i][0] = 1.0 / cphi
            Phi[i][1] = -eps2 / cphi
        Phi = apply_feature_omega_beta(Phi, beta)

    else:
        raise RuntimeError(f"Unknown env {env}")

    P = normalize_rows(P)
    Phi = normalize_phi_infty_sq(Phi)
    return gamma, P, Phi


def save_matrix(path: Path, M: list[list[float]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        wr = csv.writer(f, delimiter="\t")
        for row in M:
            wr.writerow([f"{v:.17g}" for v in row])


def save_vector(path: Path, v: list[float]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        wr = csv.writer(f, delimiter="\t")
        wr.writerow([f"{x:.17g}" for x in v])


def parse_kstep_output(text: str, eps: float) -> tuple[int, float, float, float, float, float]:
    del eps  # t_mix_upper is read directly from binary output table.

    best_k = -1
    t_mix_best = float("inf")
    delta_best = float("nan")
    alpha = float("nan")
    tau_alpha = float("nan")
    C_hat = float("nan")

    table_mode = False
    for line in text.splitlines():
        ls = line.strip()
        if not ls:
            continue
        if ls.startswith("best_k"):
            try:
                best_k = int(ls.split("=")[-1].strip())
            except ValueError:
                best_k = -1
            continue
        if ls.startswith("t_mix_upper(best_k, eps)"):
            try:
                t_mix_best = float(ls.split("=")[-1].strip())
            except ValueError:
                t_mix_best = float("inf")
            continue
        if ls.startswith("k, delta(P^k)"):
            table_mode = True
            continue
        if not table_mode:
            continue
        if not ls[0].isdigit():
            continue

        parts = [p.strip() for p in ls.split(",")]
        if len(parts) < 6:
            continue
        try:
            k = int(parts[0])
            delta_k = float(parts[1])
            alpha_k = float(parts[2])
            tau_k = float(parts[3])
            C_k = float(parts[4])
            t_mix_k = float(parts[5])
        except ValueError:
            continue

        if k == best_k:
            delta_best = delta_k
            alpha = alpha_k
            tau_alpha = tau_k
            C_hat = C_k
            t_mix_best = t_mix_k

    if best_k < 1:
        return -1, float("nan"), float("nan"), float("nan"), float("nan"), float("inf")

    return best_k, delta_best, alpha, tau_alpha, C_hat, t_mix_best


def run_kstep(tdmix_bin: Path, p_path: Path, K: int, eps: float) -> tuple[int, float, float, float, float, float]:
    cmd = [str(tdmix_bin), str(p_path), str(K), f"{eps:.17g}", "0"]
    proc = subprocess.run(cmd, check=True, capture_output=True, text=True)
    return parse_kstep_output(proc.stdout, eps)


def exact_duplicate_groups(instances: list[Instance]) -> list[list[Instance]]:
    used = [False] * len(instances)
    groups: list[list[Instance]] = []
    for i, a in enumerate(instances):
        if used[i]:
            continue
        used[i] = True
        grp = [a]
        for j in range(i + 1, len(instances)):
            if used[j]:
                continue
            b = instances[j]
            same_omega = abs(a.omega - b.omega) <= 1e-10 * max(1.0, abs(a.omega), abs(b.omega))
            same_kappa = abs(a.kappa - b.kappa) <= 1e-10 * max(1.0, abs(a.kappa), abs(b.kappa))
            same_tau = (
                (math.isinf(a.tau_proxy) and math.isinf(b.tau_proxy))
                or (
                    math.isfinite(a.tau_proxy)
                    and math.isfinite(b.tau_proxy)
                    and abs(a.tau_proxy - b.tau_proxy) <= 1e-10 * max(1.0, abs(a.tau_proxy), abs(b.tau_proxy))
                )
            )
            if same_omega and same_kappa and same_tau:
                used[j] = True
                grp.append(b)
        if len(grp) > 1:
            groups.append(grp)
    return groups


def tau_regime(t: float) -> str:
    if math.isinf(t):
        return "inf"
    if t <= 10:
        return "fast<=1e1"
    if t <= 1e3:
        return "mid<=1e3"
    if t <= 1e6:
        return "slow<=1e6"
    return "vslow>1e6"


def write_master_tsv(instances: list[Instance], out_tsv: Path) -> None:
    out_tsv.parent.mkdir(parents=True, exist_ok=True)
    with out_tsv.open("w", newline="", encoding="utf-8") as f:
        wr = csv.writer(f, delimiter="\t")
        wr.writerow(
            [
                "instance_key",
                "env",
                "case_id",
                "control_key",
                "control_value",
                "gamma",
                "n_states",
                "d",
                "omega",
                "kappa",
                "lambda_min_A_plus_AT_over_2",
                "phi_max_sq",
                "tau_proxy",
                "best_k",
                "delta_bestk",
                "alpha_hat",
                "tau_alpha",
                "C_hat",
                "t_mix_upper_alpha_eps1e-6",
                "theta_star_norm",
                "r_max",
                "R_oracle",
                "R_upper",
                "matrix_dir",
            ]
        )
        for x in instances:
            wr.writerow(
                [
                    x.key,
                    x.env,
                    x.case_id,
                    x.control_key,
                    x.control_value,
                    f"{x.gamma:.17g}",
                    x.n,
                    x.d,
                    f"{x.omega:.17g}",
                    f"{x.kappa:.17g}",
                    f"{x.lambda_min_A_plus_AT_over_2:.17g}",
                    f"{x.phi_max_sq:.17g}",
                    f"{x.tau_proxy:.17g}" if math.isfinite(x.tau_proxy) else "inf",
                    x.best_k,
                    f"{x.delta_bestk:.17g}",
                    f"{x.alpha_hat:.17g}",
                    f"{x.tau_alpha:.17g}" if math.isfinite(x.tau_alpha) else "inf",
                    f"{x.C_hat:.17g}" if math.isfinite(x.C_hat) else "inf",
                    f"{x.t_mix_upper_alpha:.17g}" if math.isfinite(x.t_mix_upper_alpha) else "inf",
                    f"{x.theta_star_norm:.17g}",
                    f"{x.r_max:.17g}",
                    f"{x.R_oracle:.17g}",
                    f"{x.R_upper:.17g}",
                    str(x.matrix_dir),
                ]
            )


def write_summary_md(
    instances: list[Instance],
    out_md: Path,
    out_tsv: Path,
    matrix_root: Path,
    methods_per_instance: int,
    n_schedules: int,
    n_projections: int,
) -> None:
    by_env: dict[str, list[Instance]] = {e: [] for e in ENV_ORDER}
    for x in instances:
        by_env[x.env].append(x)
    for e in ENV_ORDER:
        by_env[e].sort(key=lambda z: int(z.case_id))

    dup = exact_duplicate_groups(instances)
    bins: dict[tuple[int, str], list[Instance]] = {}
    for x in instances:
        b = (int(math.floor(math.log10(max(x.omega, 1e-300)))), tau_regime(x.tau_proxy))
        bins.setdefault(b, []).append(x)

    strict_remove = sum(len(g) - 1 for g in dup)
    env_formula = {
        "toyexample": [
            "State/action-free Markov chain with `n=50`, `d=5`, `gamma=0.99`.",
            "Transition: `P(i,i)=0.1`, `P(i,i+1 mod 50)=0.6`, `P(i,i-1 mod 50)=0.3`.",
            "Feature: random `Phi[s,j] ~ Uniform(0,10)` from SplitMix64(seed=114514), then `feature_omega_beta` scales columns `j>=2`, then global `phi_infty^2` normalization.",
        ],
        "E1": [
            "2-state alternating chain (`n=2`, `d=1`, `gamma=0.99`).",
            "Transition: `P=[[eps1,1-eps1],[1-eps1,eps1]]`, default `eps1=1e-3`.",
            "Feature: `phi(1)=eps2/sqrt(1+eps2^2)`, `phi(2)=1/sqrt(1+eps2^2)` then normalized to `phi_infty^2=1`.",
        ],
        "E2": [
            "2-state sticky chain (`n=2`, `d=2`, `gamma=0.99`).",
            "Transition: `P=[[1-eps1,eps1],[eps1,1-eps1]]`, default `eps1=1e-3`.",
            "Feature: `Phi=[[1/cphi,0],[1/cphi,eps2/cphi]]`, `cphi=sqrt(2+eps2^2)`, then normalized.",
        ],
        "E3": [
            "3-state metastable trap (`n=3`, `d=2`, `gamma=0.99`) [renumbered from legacy E4].",
            "Transition: `P=[[0,1,0],[1-eps1,0,eps1],[eps1,0,1-eps1]]`, default `eps1=1e-3`.",
            "Feature: `Phi=[[1/cphi,0],[1/cphi,eps2/cphi],[0,0]]`, `cphi=sqrt(2+eps2^2)`, then normalized.",
        ],
        "E4": [
            "Ring chain (`n=m=20`, `d=20`, `gamma=0.99`) [renumbered from legacy E5].",
            "Transition: `P(i,i)=eps1`, `P(i,i+1 mod m)=1-eps1`, default `eps1=1e-2`.",
            "Feature: identity `I_m`, then `feature_omega_beta` on columns `j>=2`, then normalized.",
        ],
        "E5": [
            "Conveyor-reset chain (`n=m+1=21`, `d=20`, `gamma=0.99`) [renumbered from legacy E6].",
            "Transition: state 0 sticks/jumps to 1; states `1..m-1` deterministically advance; state `m` resets to 0.",
            "Feature: shifted identity (`Phi[i+1,i]=1`), then `feature_omega_beta` and normalization.",
        ],
        "E6": [
            "Ring harmonic features (`n=m=32`, `d=2`, `gamma=0.99`) [renumbered from legacy E8].",
            "Transition: ring form with `m=32` and default `eps1=1e-2`.",
            "Feature: `Phi[i,:]=[cos(2pi i/m), sin(2pi i/m)]/sqrt(m)`, then `feature_omega_beta` and normalization.",
        ],
        "E7": [
            "Excursion arc with reset hub (`n=m+1=65`, `d=2`, `gamma=0.99`) [renumbered from legacy E9].",
            "Transition: `0->1` deterministically; `i->i+1` with prob `1-eps1` and `i->0` with prob `eps1`; last state resets to 0.",
            "Feature: hub state all-zero; arc states use `[cos(alpha_i), sin(alpha_i)]/sqrt(m)`, `alpha_i=alpha_max*(i/m)`.",
        ],
        "E8": [
            "4-cycle bow-tie features (`n=4`, `d=2`, `gamma=0.99`) [renumbered from legacy E10].",
            "Transition: ring with `m=4`, `eps1=1e-2`.",
            "Feature rows: `[1,0]`, `[1,eps2]`, `[0,1]`, `[-1,eps2]`, all scaled by `1/sqrt(3)` then normalized.",
        ],
        "E9": [
            "Reflecting corridor (`n=m+1=51`, `d=2`, `gamma=0.99`) [renumbered from legacy E11].",
            "Transition: endpoint self-loop 0.75 + inward move 0.25; interior `[left,stay,right]=[0.25,0.5,0.25]`.",
            "Feature: `Phi[i,:]=[1/cphi, eps2*(2i-m)/(m*cphi)]`, `cphi=sqrt((m+1)(1+eps2^2))`, then normalized.",
        ],
        "E10": [
            "Two-cluster block chain (`n=2k=20`, `d=2`, `gamma=0.99`) [renumbered from legacy E12].",
            "Transition: intra-cluster prob `(1-eps1)` and inter-cluster prob `eps1`, both spread uniformly across destination cluster.",
            "Feature: first cluster `[1, +eps2]/sqrt(2k)`, second cluster `[1, -eps2]/sqrt(2k)`, then normalized.",
        ],
    }

    total_cases = len(instances)

    with out_md.open("w", encoding="utf-8") as f:
        f.write(f"# summary_instance.md ({total_cases} renumbered TD instances)\n\n")
        f.write("Date: 2026-04-04\n\n")

        f.write("## A. Reproducibility + Definitions\n\n")
        f.write("資料來源\n")
        f.write(f"- Master table: `{out_tsv}`\n")
        f.write(f"- Matrix dump root: `{matrix_root}`\n")
        f.write("- Generator: `scripts/generate_summary_instance_md.py`\n")
        f.write("- k-step estimator: `cpp/tdmix_kstep` with `K=256`, `eps=1e-6`\n\n")

        f.write("統一定義\n")
        f.write(f"- `phi_infty^2 = max_s ||phi(s)||_2^2`（本批 {total_cases} cases 都被正規化到接近 1）。\n")
        f.write("- Stepsize scaling 全部用分母形式：`alpha_t = 1 / (c * g(t))`。\n")
        f.write("- `omega`: `G` 最小特徵值；`kappa=lambda_max(G)/omega`。\n")
        f.write("- `lambda_min((A+A^T)/2)`: 其中 `A = Phi^T D (I-gamma P) Phi` 為 standard TD mean matrix。\n")
        f.write("- `tau_proxy`: 由 transition mixing 代理量（由 C++ 主程式輸出）。\n")
        f.write("- `alpha_hat`: k-step Dobrushin 表中 `best_k` 那列的 `alpha_k = delta(P^k)^(1/k)`。\n")
        f.write("- `1/(1-alpha_hat)`: 即 `tau_alpha_hat`（若 `alpha_hat=1` 則為 `inf`）。\n")
        f.write("- `C_hat`: `best_k` 那列的 `C_k=max_{0<=r<k} delta(P^r)`。\n")
        f.write("- `t_mix_upper_alpha`: `best_k` 那列的理論 upper bound `t_mix_upper_k(eps)`。\n")
        f.write("- Projection 半徑：`R_oracle = ||theta^*||_2`，`R_upper = 2*r_max/(sqrt(omega)*(1-gamma)^(3/2))`。\n")
        f.write("- Objective-A 對應 C++ 內 `A2=(1-gamma)Diag(D)+gamma*S`（`S` 為對稱化 Dirichlet 結構），紀錄欄位為 `E_A[||Vbar_t-V*||^2]`。\n\n")
        f.write("- 編號規則已更新：刪除 legacy `E3`、`E7` 後，後續環境遞補為 `E1..E10`。\n\n")

        f.write("## B. Environment-Level TD Instance Definitions\n\n")
        f.write(f"以下先給每個 environment 的生成規則；{total_cases} 個 case 是在同一規則下改 `eps2` 或 `feature_omega_beta` 的 4-level sweep。\n\n")
        for env in ENV_ORDER:
            f.write(f"### {env}\n\n")
            f.write(f"- `gamma` (all cases): `{fmt(by_env[env][0].gamma)}`\n")
            for line in env_formula[env]:
                f.write(f"- {line}\n")
            f.write("\n")

        f.write(f"## C. {total_cases}-Case Full Quantity Table\n\n")
        f.write("| instance_key | env | case | control | value | gamma | n | d | omega | kappa | lambda_min((A+A^T)/2) | phi_inf^2 | tau_proxy | best_k | delta(P^best_k) | alpha_hat | 1/(1-alpha_hat) | C_hat | t_mix_upper_alpha | theta* norm | R_oracle | R_upper |\n")
        f.write("|---|---|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|\n")
        for x in instances:
            f.write(
                "| "
                + " | ".join(
                    [
                        x.key,
                        x.env,
                        x.case_id,
                        x.control_key,
                        x.control_value,
                        fmt(x.gamma),
                        str(x.n),
                        str(x.d),
                        fmt(x.omega),
                        fmt(x.kappa),
                        fmt(x.lambda_min_A_plus_AT_over_2),
                        fmt(x.phi_max_sq),
                        fmt(x.tau_proxy),
                        str(x.best_k),
                        fmt(x.delta_bestk),
                        fmt(x.alpha_hat),
                        fmt(x.tau_alpha),
                        fmt(x.C_hat),
                        fmt(x.t_mix_upper_alpha),
                        fmt(x.theta_star_norm),
                        fmt(x.R_oracle),
                        fmt(x.R_upper),
                    ]
                )
                + " |\n"
            )
        f.write("\n")

        f.write("## D. Per-Environment Matrix Dumps (P, D, Phi)\n\n")
        f.write("每個 case 的完整矩陣檔都已輸出到 `matrix_dir`：`P.tsv`, `D.tsv`, `Phi.tsv`。\n")
        f.write("同一 env 的 4 個 case 只改 feature-sweep 參數時，`P` 與 `D` 相同；`Phi` 隨 sweep 改變。\n\n")

        for env in ENV_ORDER:
            f.write(f"### {env}\n\n")
            x0 = by_env[env][0]
            d_full = ", ".join(fmt(v, 8) for v in x0.D)
            f.write(f"- Full D vector (shared transition for this env): [{d_full}]\n")
            f.write(f"- D length: {len(x0.D)}\n\n")
            f.write("| case | control | value | omega | kappa | lambda_min((A+A^T)/2) | tau_proxy | best_k | alpha_hat | 1/(1-alpha_hat) | t_mix_upper_alpha | P.tsv | D.tsv | Phi.tsv |\n")
            f.write("|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|---|---|\n")
            for x in by_env[env]:
                f.write(
                    "| "
                    + " | ".join(
                        [
                            x.case_id,
                            x.control_key,
                            x.control_value,
                            fmt(x.omega),
                            fmt(x.kappa),
                            fmt(x.lambda_min_A_plus_AT_over_2),
                            fmt(x.tau_proxy),
                            str(x.best_k),
                            fmt(x.alpha_hat),
                            fmt(x.tau_alpha),
                            fmt(x.t_mix_upper_alpha),
                            str(x.matrix_dir / "P.tsv"),
                            str(x.matrix_dir / "D.tsv"),
                            str(x.matrix_dir / "Phi.tsv"),
                        ]
                    )
                    + " |\n"
                )
            f.write("\n")

        f.write("## E. Redundancy Analysis for Hard-Instance Challenge\n\n")
        f.write("### E.1 Strict duplicate groups (same omega/kappa/tau_proxy up to numerical tolerance)\n\n")
        if not dup:
            f.write("- No strict duplicates found.\n")
        else:
            for g in dup:
                names = [f"{x.env}(case{x.case_id}, {x.control_key}={x.control_value})" for x in g]
                f.write(f"- group size {len(g)}: " + " ; ".join(names) + "\n")
        f.write("\n")

        f.write("### E.2 Repeated hardness bins\n\n")
        f.write("- Bin signature: `(floor(log10(omega)), tau_regime)`.\n")
        f.write("- `tau_regime`: `fast<=1e1`, `mid<=1e3`, `slow<=1e6`, `vslow>1e6`, `inf`.\n\n")
        f.write("| omega_decade | tau_regime | count | members |\n")
        f.write("|---:|---|---:|---|\n")
        for b in sorted(bins.keys(), key=lambda t: (t[0], t[1])):
            mem = bins[b]
            if len(mem) <= 1:
                continue
            names = ", ".join(f"{m.env}:case{m.case_id}" for m in mem)
            f.write(f"| {b[0]} | {b[1]} | {len(mem)} | {names} |\n")
        f.write("\n")

        f.write("### E.3 Suggested pruning policy\n\n")
        f.write(f"- Conservative dedup only: `{total_cases} -> {total_cases - strict_remove}`.\n")
        f.write("- Immediate safe drops: duplicate groups listed in E.1.\n")
        f.write("- Aggressive pruning rule: keep one representative per repeated hardness bin in E.2, while preserving distinct transition topology classes (`ring`, `conveyor`, `hub-reset`, `block-cluster`, `metastable-3state`).\n\n")

        f.write("## F. Plot Plan (v2 pipeline)\n\n")
        f.write("### F.1 Inputs and logged columns used by `scripts/plot_suite_v2.py`\n\n")
        f.write("- `manifest.tsv`: case metadata + file pointers (`agg_file`, `run_file`, `schedule`, `projection`, `param_value`, `omega`, `tau_proxy`, `kappa`, `gamma`).\n")
        f.write("- `agg_*.csv` columns used:\n")
        f.write("  - `timestep`\n")
        f.write("  - `E_D[||Vbar_t - V*||^2]`\n")
        f.write("  - `E_A[||Vbar_t - V*||^2]`\n")
        f.write("  - `max_i<=T ||theta_i||^2`\n")
        f.write("  - `||theta^*||^2`\n")
        f.write("- `runs_*.csv` columns used:\n")
        f.write("  - `diverged` (for divergence rate)\n\n")

        f.write("### F.2 Figure families from `scripts/plot_suite_v2.py`\n\n")
        f.write("1. `bestcurves_by_c (metric D)`\n")
        f.write("- Output: `{env}__bestcurves_by_c__metric-D__omega-grid-{rows}x{cols}.png`\n")
        f.write("- One subplot per omega/case; each line is a method `(schedule, projection)` at its best `c` under final `D`.\n")
        f.write("- x=`timestep` (log), y=`suboptimality D` (log).\n\n")

        f.write("2. `bestcurves_by_c (metric D+A)`\n")
        f.write("- Output: `{env}__bestcurves_by_c__metric-DA__omega-grid-{rows}x{cols}.png`\n")
        f.write("- Same as #1 but best-`c` selection and y-axis use final `D+A`.\n\n")

        f.write("3. `algo-finalgrid per method`\n")
        f.write("- Output: `{env}__algo-finalgrid__method-{method_id}__rows-omega__cols-ratio-div-D-DA.png`\n")
        f.write("- One figure per method.\n")
        f.write("- Layout: rows=omega/case, cols=[ratio, divergence, final D, final D+A], x=`c` (log).\n\n")

        f.write("4. `algo-curves-by-c (metric D)`\n")
        f.write("- Output: `{env}__algo-curves-by-c__metric-D__method-{method_id}__omega-grid-{rows}x{cols}.png`\n")
        f.write("- One figure per method; one subplot per omega/case; one curve per `c`.\n")
        f.write("- x=`timestep` (log), y=`suboptimality D` (log).\n\n")

        f.write("5. `algo-curves-by-c (metric D+A)`\n")
        f.write("- Output: `{env}__algo-curves-by-c__metric-DA__method-{method_id}__omega-grid-{rows}x{cols}.png`\n")
        f.write("- Same as #4 but y is `suboptimality D+A`.\n\n")

        f.write("6. `omega-method-bestc overlay (metric D)`\n")
        f.write("- Output: `{env}__omega-{idx}-{omega}__methods-bestc__metric-D.png`\n")
        f.write("- One figure per omega/case; each line is one method at its best `c` under `D`.\n\n")

        f.write("7. `omega-method-bestc overlay (metric D+A)`\n")
        f.write("- Output: `{env}__omega-{idx}-{omega}__methods-bestc__metric-DA.png`\n")
        f.write("- Same as #6 but best-`c` criterion is final `D+A`.\n\n")

        f.write("8. `omega_final_error scatter (metric D)`\n")
        f.write("- Output: `{env}__omega_final_error_D__method-{method_id}.png`\n")
        f.write("- One figure per method: x=`omega`, y=`final D`, point color=`c`.\n\n")

        f.write("9. `omega_final_error scatter (metric D+A)`\n")
        f.write("- Output: `{env}__omega_final_error_DA__method-{method_id}.png`\n")
        f.write("- One figure per method: x=`omega`, y=`final D+A`, point color=`c`.\n\n")

        f.write("10. `plot inventory`\n")
        f.write("- Output: `plot_inventory_v2.tsv` (all generated PNG filenames for that run dir).\n\n")

        f.write("11. `embedded report`\n")
        f.write("- Generated by `scripts/generate_embedded_report_v2.py`.\n")
        f.write("- Embeds all PNG from each run directory and optionally `instance_structure_plots/*.png` + alpha table TSV.\n\n")

        f.write("### F.3 Dynamic count formulas (omega count and instance count can grow)\n\n")
        n_env = sum(1 for e in ENV_ORDER if by_env[e])
        n_case = len(instances)
        f.write(f"- Current summary has `E={n_env}` envs and `N_case={n_case}` cases.\n")
        f.write(
            f"- Current method count from manifest: `M={methods_per_instance}` "
            f"(`{n_schedules} schedules x {n_projections} projections`).\n"
        )
        f.write("- Per env with `C_e` cases, v2 PNG count is:\n")
        f.write("  - `N_env = 2 + 5M + 2C_e`\n")
        f.write("  - (`2` bestcurves) + (`M` finalgrid) + (`2M` curves-by-c) + (`2C_e` methods-bestc) + (`2M` omega-final-error)\n")
        f.write("- Across all envs:\n")
        f.write("  - `N_total = sum_e (2 + 5M + 2C_e)`\n")
        f.write("  - if all envs share same case count `C`: `N_total = E * (2 + 5M + 2C)`\n\n")

        structure_png = 3 * n_case
        f.write("### F.4 Optional structure visuals\n\n")
        f.write("- `P_heatmap` per case: x=next-state, y=state, color=`P[s,s']`.\n")
        f.write("- `Phi_heatmap` per case: x=feature index, y=state, color=`Phi[s,j]`.\n")
        f.write("- `D_bar` per case: x=state index, y=`D[s]`.\n")
        f.write(f"- If all structure plots are present: `3 * N_case = {structure_png}` PNG.\n")


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Generate summary_instance.md")
    p.add_argument("--manifest-root", default="verification/new_instance_smoke")
    p.add_argument("--out-md", default="verification/summary_instance.md")
    p.add_argument("--out-tsv", default="verification/summary_instance_44cases.tsv")
    p.add_argument("--matrix-root", default="verification/instance_matrices_20260404")
    p.add_argument("--kstep-K", type=int, default=256)
    p.add_argument("--kstep-eps", type=float, default=1e-6)
    p.add_argument("--tdmix-bin", default="cpp/tdmix_kstep")
    return p.parse_args()


def main() -> None:
    args = parse_args()
    manifest_root = Path(args.manifest_root).resolve()
    out_md = Path(args.out_md).resolve()
    out_tsv = Path(args.out_tsv).resolve()
    matrix_root = Path(args.matrix_root).resolve()
    tdmix_bin = Path(args.tdmix_bin).resolve()

    if not tdmix_bin.exists():
        raise RuntimeError(f"tdmix binary not found: {tdmix_bin}")

    methods_per_instance, n_schedules, n_projections = method_grid_info(manifest_root)
    rows = load_case_rows(manifest_root)
    instances: list[Instance] = []

    for row in rows:
        params = dict(DEFAULT_PARAMS[row.env])
        params.update(row.metadata)
        gamma, P, Phi = build_env(row.env, params)
        D = stationary_distribution(P)
        lambda_min_A_plus_AT_over_2 = compute_lambda_min_A_plus_AT_over_2(P, Phi, D, gamma)

        control_key = "feature_omega_beta" if row.env in {"toyexample", "E4", "E5", "E6", "E7"} else "eps2"
        control_value = params.get(control_key, "n/a")

        key = f"{row.env}_case{row.case_id}_{control_key}_{str(control_value).replace('.', 'p')}".replace("-", "m")
        case_dir = matrix_root / key
        p_file = case_dir / "P.tsv"
        d_file = case_dir / "D.tsv"
        phi_file = case_dir / "Phi.tsv"

        save_matrix(p_file, P)
        save_vector(d_file, D)
        save_matrix(phi_file, Phi)

        best_k, delta_best, alpha_hat, tau_alpha, C_hat, t_mix_upper = run_kstep(
            tdmix_bin=tdmix_bin, p_path=p_file, K=args.kstep_K, eps=args.kstep_eps
        )

        om_safe = max(row.omega, 1e-12)
        one_minus_g = max(1e-12, 1.0 - gamma)
        R_upper = 2.0 * row.r_max / (math.sqrt(om_safe) * (one_minus_g ** 1.5))

        instances.append(
            Instance(
                key=key,
                env=row.env,
                case_id=row.case_id,
                control_key=control_key,
                control_value=str(control_value),
                gamma=gamma,
                n=len(P),
                d=len(Phi[0]) if Phi else 0,
                omega=row.omega,
                kappa=row.kappa,
                lambda_min_A_plus_AT_over_2=lambda_min_A_plus_AT_over_2,
                phi_max_sq=row.phi_max_sq,
                tau_proxy=row.tau_proxy,
                theta_star_norm=row.theta_star_norm,
                r_max=row.r_max,
                R_oracle=row.theta_star_norm,
                R_upper=R_upper,
                best_k=best_k,
                delta_bestk=delta_best,
                alpha_hat=alpha_hat,
                tau_alpha=tau_alpha,
                C_hat=C_hat,
                t_mix_upper_alpha=t_mix_upper,
                D=D,
                matrix_dir=case_dir,
            )
        )

    instances.sort(key=lambda x: (ENV_ORDER.index(x.env), int(x.case_id)))

    write_master_tsv(instances, out_tsv)
    write_summary_md(
        instances,
        out_md,
        out_tsv,
        matrix_root,
        methods_per_instance=methods_per_instance,
        n_schedules=n_schedules,
        n_projections=n_projections,
    )

    phi_vals = [x.phi_max_sq for x in instances]
    print(f"[ok] summary markdown: {out_md}")
    print(f"[ok] summary tsv: {out_tsv}")
    print(f"[ok] matrix dir: {matrix_root}")
    print(f"[check] instances={len(instances)}")
    print(f"[check] phi_max_sq min={min(phi_vals):.17g} max={max(phi_vals):.17g}")


if __name__ == "__main__":
    main()
