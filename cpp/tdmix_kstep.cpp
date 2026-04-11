#include <algorithm>
#include <cmath>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace tdmix {

using Real = long double;
using Vec = std::vector<Real>;
using Mat = std::vector<Vec>;

struct KStepRow {
    int k = -1;
    Real delta_k = 1.0L;
    Real alpha_k = 1.0L;     // delta(P^k)^(1/k)
    Real tau_alpha_k = std::numeric_limits<Real>::infinity();
    Real C_k = 1.0L;         // max_{0<=r<k} delta(P^r)
    Real t_mix_upper = std::numeric_limits<Real>::infinity();  // upper bound for eps-mixing time
};

struct KStepEstimate {
    int best_k = -1;
    Real best_t_mix_upper = std::numeric_limits<Real>::infinity();
    std::vector<Real> delta_powers;  // delta(P^k), k=0..K
    std::vector<KStepRow> rows;      // one row per k in 1..K
};

static inline Real clip01(Real x) {
    if (x < 0) return 0;
    if (x > 1) return 1;
    return x;
}

static inline std::string trim(std::string s) {
    auto not_space = [](unsigned char c) { return !std::isspace(c); };
    s.erase(s.begin(), std::find_if(s.begin(), s.end(), not_space));
    s.erase(std::find_if(s.rbegin(), s.rend(), not_space).base(), s.end());
    return s;
}

Mat read_matrix_text(const std::string& path) {
    std::ifstream fin(path);
    if (!fin) {
        throw std::runtime_error("Cannot open file: " + path);
    }

    Mat P;
    std::string line;
    while (std::getline(fin, line)) {
        auto hash_pos = line.find('#');
        if (hash_pos != std::string::npos) line = line.substr(0, hash_pos);

        for (char& c : line) {
            if (c == ',' || c == ';' || c == '\t') c = ' ';
        }

        line = trim(line);
        if (line.empty()) continue;

        std::stringstream ss(line);
        Vec row;
        Real x;
        while (ss >> x) row.push_back(x);
        if (!row.empty()) P.push_back(std::move(row));
    }
    return P;
}

void check_square(const Mat& A) {
    if (A.empty()) throw std::runtime_error("Matrix is empty.");
    const int n = static_cast<int>(A.size());
    for (int i = 0; i < n; ++i) {
        if (static_cast<int>(A[i].size()) != n) {
            throw std::runtime_error("Matrix must be square.");
        }
    }
}

void check_row_stochastic(const Mat& P, Real tol = 1e-12L) {
    check_square(P);
    const int n = static_cast<int>(P.size());
    for (int i = 0; i < n; ++i) {
        Real s = 0;
        for (int j = 0; j < n; ++j) {
            if (P[i][j] < -tol) {
                throw std::runtime_error("Matrix has a negative entry beyond tolerance.");
            }
            s += P[i][j];
        }
        if (std::fabs(static_cast<double>(s - 1.0L)) > static_cast<double>(tol)) {
            std::ostringstream oss;
            oss << "Row " << i << " sums to "
                << std::setprecision(18) << static_cast<double>(s)
                << ", not 1 within tolerance.";
            throw std::runtime_error(oss.str());
        }
    }
}

Mat identity(int n) {
    Mat I(n, Vec(n, 0));
    for (int i = 0; i < n; ++i) I[i][i] = 1;
    return I;
}

Mat transpose(const Mat& A) {
    check_square(A);
    const int n = static_cast<int>(A.size());
    Mat T(n, Vec(n, 0));
    for (int i = 0; i < n; ++i) {
        for (int j = 0; j < n; ++j) T[j][i] = A[i][j];
    }
    return T;
}

Mat multiply(const Mat& A, const Mat& B) {
    check_square(A);
    check_square(B);
    const int n = static_cast<int>(A.size());
    if (static_cast<int>(B.size()) != n) {
        throw std::runtime_error("Dimension mismatch in multiply.");
    }

    Mat C(n, Vec(n, 0));
    for (int i = 0; i < n; ++i) {
        for (int k = 0; k < n; ++k) {
            const Real aik = A[i][k];
            if (aik == 0) continue;
            for (int j = 0; j < n; ++j) C[i][j] += aik * B[k][j];
        }
    }
    return C;
}

Real l1_distance(const Vec& a, const Vec& b) {
    if (a.size() != b.size()) {
        throw std::runtime_error("Dimension mismatch in l1_distance.");
    }
    Real s = 0;
    for (size_t i = 0; i < a.size(); ++i) s += std::fabs(static_cast<double>(a[i] - b[i]));
    return s;
}

Real tv_distance(const Vec& a, const Vec& b) {
    return 0.5L * l1_distance(a, b);
}

// Dobrushin coefficient:
//   delta(P) = 1/2 * max_{i,j} || row_i(P) - row_j(P) ||_1
Real dobrushin_delta(const Mat& P) {
    check_square(P);
    const int n = static_cast<int>(P.size());
    Real best = 0;
    for (int i = 0; i < n; ++i) {
        for (int j = i + 1; j < n; ++j) {
            Real s = 0;
            for (int r = 0; r < n; ++r) s += std::fabs(static_cast<double>(P[i][r] - P[j][r]));
            best = std::max(best, 0.5L * s);
        }
    }
    return clip01(best);
}

Vec solve_linear_system(Mat A, Vec b, Real tol = 1e-18L) {
    const int n = static_cast<int>(A.size());
    if (n == 0 || static_cast<int>(b.size()) != n) {
        throw std::runtime_error("Bad dimensions in solve_linear_system.");
    }

    for (int i = 0; i < n; ++i) {
        int pivot = i;
        for (int r = i + 1; r < n; ++r) {
            if (std::fabs(static_cast<double>(A[r][i])) > std::fabs(static_cast<double>(A[pivot][i]))) pivot = r;
        }
        if (std::fabs(static_cast<double>(A[pivot][i])) <= static_cast<double>(tol)) {
            throw std::runtime_error(
                "Singular or ill-conditioned system in stationary_distribution().");
        }
        if (pivot != i) {
            std::swap(A[pivot], A[i]);
            std::swap(b[pivot], b[i]);
        }

        const Real diag = A[i][i];
        for (int j = i; j < n; ++j) A[i][j] /= diag;
        b[i] /= diag;

        for (int r = 0; r < n; ++r) {
            if (r == i) continue;
            const Real factor = A[r][i];
            if (factor == 0) continue;
            for (int j = i; j < n; ++j) A[r][j] -= factor * A[i][j];
            b[r] -= factor * b[i];
        }
    }
    return b;
}

// Solve pi^T P = pi^T, sum_i pi_i = 1.
Vec stationary_distribution(const Mat& P, Real tol = 1e-18L) {
    check_row_stochastic(P);
    const int n = static_cast<int>(P.size());

    Mat A = transpose(P);
    for (int i = 0; i < n; ++i) A[i][i] -= 1.0L;
    Vec b(n, 0.0L);

    for (int j = 0; j < n; ++j) A[n - 1][j] = 1.0L;
    b[n - 1] = 1.0L;

    Vec pi = solve_linear_system(A, b, tol);

    Real s = 0;
    for (Real& x : pi) {
        if (std::fabs(static_cast<double>(x)) < static_cast<double>(100 * tol)) x = 0;
        if (x < 0 && x > -1000 * tol) x = 0;
        s += x;
    }
    if (s <= 0) {
        throw std::runtime_error("Failed to obtain a valid stationary distribution.");
    }
    for (Real& x : pi) x /= s;
    return pi;
}

std::vector<Real> max_tv_curve_to_stationary(const Mat& P, const Vec& pi, int T) {
    check_row_stochastic(P);
    const int n = static_cast<int>(P.size());
    if (static_cast<int>(pi.size()) != n) {
        throw std::runtime_error("Bad pi dimension.");
    }

    std::vector<Real> curve(T + 1, 0.0L);
    Mat Pt = identity(n); // rows = e_i^T P^t
    for (int t = 0; t <= T; ++t) {
        Real worst = 0;
        for (int i = 0; i < n; ++i) {
            worst = std::max(worst, tv_distance(Pt[i], pi));
        }
        curve[t] = worst;
        if (t < T) Pt = multiply(Pt, P);
    }
    return curve;
}

int exact_mixing_time_eps(const std::vector<Real>& curve, Real eps) {
    for (int t = 0; t < static_cast<int>(curve.size()); ++t) {
        if (curve[t] <= eps) return t;
    }
    return -1;
}

static Real safe_pow(Real base, Real exp) {
    if (base <= 0.0L) {
        if (base == 0.0L) return 0.0L;
        return std::numeric_limits<Real>::quiet_NaN();
    }
    return std::exp(exp * std::log(base));
}

// k-step Dobrushin estimate:
// For each k = 1..K, let delta_k = delta(P^k), C_k = max_{0<=r<k} delta(P^r).
// Then for t = qk + r (0<=r<k):
//   delta(P^t) <= C_k * delta_k^q.
// Since sup_x ||xP^t - pi||_TV <= delta(P^t), an eps-mixing upper bound is
//   t_mix(eps) <= k * ceil( log(eps/C_k) / log(delta_k) )   (delta_k in (0,1)).
KStepEstimate estimate_mixing_kstep_dobrushin(const Mat& P, int K, Real eps) {
    check_row_stochastic(P);
    if (K < 1) throw std::runtime_error("K must be >= 1.");
    if (!(eps > 0.0L && eps < 1.0L)) throw std::runtime_error("eps must be in (0,1).");

    KStepEstimate out;
    out.delta_powers.assign(K + 1, 1.0L);
    out.rows.reserve(static_cast<size_t>(K));

    Mat Pk = identity(static_cast<int>(P.size()));
    for (int k = 1; k <= K; ++k) {
        Pk = multiply(Pk, P);
        out.delta_powers[k] = dobrushin_delta(Pk);
    }

    for (int k = 1; k <= K; ++k) {
        KStepRow row;
        row.k = k;
        row.delta_k = clip01(out.delta_powers[k]);

        row.alpha_k = (row.delta_k > 0.0L) ? clip01(safe_pow(row.delta_k, 1.0L / static_cast<Real>(k))) : 0.0L;
        row.tau_alpha_k = (row.alpha_k < 1.0L) ? (1.0L / (1.0L - row.alpha_k)) : std::numeric_limits<Real>::infinity();

        row.C_k = 0.0L;
        for (int r = 0; r < k; ++r) {
            row.C_k = std::max(row.C_k, out.delta_powers[r]);
        }
        row.C_k = std::max(row.C_k, 1e-30L);

        if (row.delta_k == 0.0L) {
            // For any t >= k, q >= 1, so bound becomes 0.
            row.t_mix_upper = static_cast<Real>(k);
        } else if (row.delta_k < 1.0L) {
            // Need C_k * delta_k^q <= eps.
            // If eps >= C_k then q=0 suffices, t=0 upper bound.
            Real q = 0.0L;
            if (eps < row.C_k) {
                const Real num = std::log(eps / row.C_k);
                const Real den = std::log(row.delta_k); // negative
                q = std::ceil(num / den);
                if (q < 0.0L) q = 0.0L;
            }
            row.t_mix_upper = static_cast<Real>(k) * q;
        } else {
            row.t_mix_upper = std::numeric_limits<Real>::infinity();
        }

        out.rows.push_back(row);

        if (std::isfinite(static_cast<double>(row.t_mix_upper))) {
            if (!(std::isfinite(static_cast<double>(out.best_t_mix_upper))) || row.t_mix_upper < out.best_t_mix_upper ||
                (row.t_mix_upper == out.best_t_mix_upper && row.k < out.best_k)) {
                out.best_t_mix_upper = row.t_mix_upper;
                out.best_k = row.k;
            }
        }
    }

    return out;
}

void print_vector(const Vec& v, const std::string& name) {
    std::cout << name << " = [";
    for (size_t i = 0; i < v.size(); ++i) {
        if (i) std::cout << ", ";
        std::cout << std::setprecision(18) << static_cast<double>(v[i]);
    }
    std::cout << "]\n";
}

} // namespace tdmix

int main(int argc, char** argv) {
    using namespace tdmix;

    if (argc < 2) {
        std::cerr
            << "Usage:\n"
            << "  " << argv[0] << " P.txt [K=32] [eps=1e-6] [T_verify=0]\n\n"
            << "Input file format: one row per line, numbers separated by "
               "spaces/commas; '#' starts comments.\n"
            << "Example:\n"
            << "  0.9 0.1\n"
            << "  0.2 0.8\n";
        return 1;
    }

    const std::string path = argv[1];
    const int K = (argc >= 3 ? std::stoi(argv[2]) : 32);
    const Real eps = (argc >= 4 ? static_cast<Real>(std::stold(argv[3])) : 1e-6L);
    const int T_verify = (argc >= 5 ? std::stoi(argv[4]) : 0);

    try {
        Mat P = read_matrix_text(path);
        check_row_stochastic(P);

        KStepEstimate est = estimate_mixing_kstep_dobrushin(P, K, eps);

        std::cout << std::setprecision(18);
        std::cout << "n = " << P.size() << "\n";
        std::cout << "eps = " << static_cast<double>(eps) << "\n";
        std::cout << "best_k (by smallest k-step upper bound) = " << est.best_k << "\n";
        std::cout << "t_mix_upper(best_k, eps) = " << static_cast<double>(est.best_t_mix_upper) << "\n";

        std::cout << "\n[k-step Dobrushin table]\n";
        std::cout << "k, delta(P^k), alpha_k=delta(P^k)^(1/k), tau_alpha_k=1/(1-alpha_k), C_k=max_{r<k}delta(P^r), t_mix_upper_k(eps)\n";
        for (const auto& row : est.rows) {
            std::cout << row.k << ", "
                      << static_cast<double>(row.delta_k) << ", "
                      << static_cast<double>(row.alpha_k) << ", "
                      << static_cast<double>(row.tau_alpha_k) << ", "
                      << static_cast<double>(row.C_k) << ", "
                      << static_cast<double>(row.t_mix_upper) << "\n";
        }

        if (T_verify > 0) {
            Vec pi = stationary_distribution(P);
            print_vector(pi, "pi");

            auto curve = max_tv_curve_to_stationary(P, pi, T_verify);
            const int t_mix = exact_mixing_time_eps(curve, eps);

            std::cout << "\n[exact verification against stationarity]\n";
            std::cout << "t_mix_exact(eps) = " << t_mix
                      << "    # -1 means not reached within T_verify\n";
            std::cout << "t, max_i TV(e_i P^t, pi)\n";
            for (int t = 0; t <= T_verify; ++t) {
                std::cout << t << ", " << static_cast<double>(curve[t]) << "\n";
            }
        }
    } catch (const std::exception& e) {
        std::cerr << "ERROR: " << e.what() << "\n";
        return 2;
    }

    return 0;
}
