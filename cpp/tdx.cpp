#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstdint>
#include <cstring>
#include <ctime>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iomanip>
#include <iostream>
#include <limits>
#include <map>
#include <numeric>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <tuple>
#include <unordered_map>
#include <utility>
#include <vector>

#ifdef _OPENMP
#include <omp.h>
#endif

namespace fs = std::filesystem;

namespace tdx {

constexpr double kEps = 1e-12;
constexpr double kDivergenceThreshold = 1e20;
constexpr double kPi = 3.141592653589793238462643383279502884;

using ParamMap = std::map<std::string, std::string>;
using SweepMap = std::map<std::string, std::vector<std::string>>;

static inline int idx2(const int r, const int c, const int ncols) {
    return r * ncols + c;
}

struct SplitMix64Rng {
    uint64_t state = 0;

    explicit SplitMix64Rng(const uint64_t seed) : state(seed) {}

    inline uint64_t next_u64() {
        state += 0x9E3779B97F4A7C15ULL;
        uint64_t z = state;
        z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
        z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
        return z ^ (z >> 31);
    }

    inline double next_unit() {
        return static_cast<double>(next_u64() >> 11) * 0x1.0p-53;
    }
};

static std::string trim(const std::string &s) {
    size_t i = 0;
    while (i < s.size() && std::isspace(static_cast<unsigned char>(s[i]))) {
        ++i;
    }
    size_t j = s.size();
    while (j > i && std::isspace(static_cast<unsigned char>(s[j - 1]))) {
        --j;
    }
    return s.substr(i, j - i);
}

static std::vector<std::string> split(const std::string &s, const char delim) {
    std::vector<std::string> out;
    std::stringstream ss(s);
    std::string tok;
    while (std::getline(ss, tok, delim)) {
        tok = trim(tok);
        if (!tok.empty()) {
            out.push_back(tok);
        }
    }
    return out;
}

static std::string to_lower(std::string s) {
    for (char &ch : s) {
        ch = static_cast<char>(std::tolower(static_cast<unsigned char>(ch)));
    }
    return s;
}

static std::string sanitize_token(std::string s) {
    s = to_lower(trim(s));
    for (char &ch : s) {
        if (ch == ' ' || ch == ',' || ch == ';' || ch == '/' || ch == '\\' || ch == '(' || ch == ')' ||
            ch == '[' || ch == ']' || ch == ':' || ch == '|' || ch == '=') {
            ch = '-';
        }
    }
    while (s.find("--") != std::string::npos) {
        s = std::string(s).replace(s.find("--"), 2, "-");
    }
    while (!s.empty() && s.front() == '-') {
        s.erase(s.begin());
    }
    while (!s.empty() && s.back() == '-') {
        s.pop_back();
    }
    return s.empty() ? "na" : s;
}

static bool starts_with(const std::string &s, const std::string &prefix) {
    return s.size() >= prefix.size() && s.compare(0, prefix.size(), prefix) == 0;
}

static std::pair<std::string, std::string> parse_key_value(const std::string &spec) {
    const auto pos = spec.find('=');
    if (pos == std::string::npos) {
        throw std::runtime_error("Expected key=value, got: " + spec);
    }
    std::string key = trim(spec.substr(0, pos));
    std::string val = trim(spec.substr(pos + 1));
    if (key.empty() || val.empty()) {
        throw std::runtime_error("Invalid key=value: " + spec);
    }
    return {key, val};
}

static double parse_double(const std::string &s) {
    try {
        size_t used = 0;
        double v = std::stod(s, &used);
        if (used != s.size()) {
            throw std::runtime_error("trailing characters");
        }
        return v;
    } catch (const std::exception &) {
        throw std::runtime_error("Failed to parse float: " + s);
    }
}

static int parse_int(const std::string &s) {
    try {
        size_t used = 0;
        int v = std::stoi(s, &used);
        if (used != s.size()) {
            throw std::runtime_error("trailing characters");
        }
        return v;
    } catch (const std::exception &) {
        throw std::runtime_error("Failed to parse int: " + s);
    }
}

static std::string canonical_env_id(const std::string &name) {
    std::string env = to_lower(trim(name));
    env.erase(std::remove_if(env.begin(), env.end(), [](char ch) {
        return ch == '-' || ch == '_' || ch == ' ';
    }), env.end());
    static const std::unordered_map<std::string, std::string> aliases = {
        {"toyexample", "toyexample"},
        {"e1", "E1"}, {"e2", "E2"}, {"e3", "E3"}, {"e4", "E4"}, {"e5", "E5"},
        {"e6", "E6"}, {"e7", "E7"}, {"e8", "E8"}, {"e9", "E9"}, {"e10", "E10"},
    };
    const auto it = aliases.find(env);
    if (it != aliases.end()) {
        return it->second;
    }
    return name;
}

static std::vector<std::string> available_environment_ids() {
    return {"toyexample", "E1", "E2", "E3", "E4", "E5", "E6", "E7", "E8", "E9", "E10"};
}

static ParamMap default_environment_params(const std::string &env_id) {
    const std::string env = canonical_env_id(env_id);
    if (env == "toyexample") {
        return {{"gamma", "0.99"}, {"seed", "114514"}, {"scale_factor", "1.0"}, {"feature_omega_beta", "1.0"}};
    }
    if (env == "E1") {
        return {{"gamma", "0.99"}, {"eps1", "1e-3"}, {"eps2", "1e-2"}, {"reward_mode", "zero"}, {"rho", "1.0"}};
    }
    if (env == "E2") {
        return {{"gamma", "0.99"}, {"eps1", "1e-3"}, {"eps2", "1e-2"}, {"reward_mode", "zero"}, {"rho", "1.0"}};
    }
    if (env == "E3") {
        return {{"gamma", "0.99"}, {"eps1", "1e-3"}, {"eps2", "1e-2"}, {"reward_mode", "zero"}, {"rho", "1.0"}};
    }
    if (env == "E4") {
        return {{"gamma", "0.99"}, {"m", "20"}, {"eps1", "1e-2"}, {"feature_omega_beta", "1.0"}, {"reward_mode", "zero"}, {"rho", "1.0"}};
    }
    if (env == "E5") {
        return {{"gamma", "0.99"}, {"m", "20"}, {"eps1", "1e-2"}, {"feature_omega_beta", "1.0"}, {"reward_mode", "zero"}, {"rho", "1.0"}};
    }
    if (env == "E6") {
        return {{"gamma", "0.99"}, {"m", "32"}, {"eps1", "1e-2"}, {"feature_omega_beta", "1.0"}, {"reward_mode", "zero"}, {"rho", "1.0"}};
    }
    if (env == "E7") {
        return {{"gamma", "0.99"}, {"m", "64"}, {"eps1", "1e-2"}, {"alpha_max", "1.5707963267948966"}, {"feature_omega_beta", "1.0"}, {"reward_mode", "zero"}, {"rho", "1.0"}};
    }
    if (env == "E8") {
        return {{"gamma", "0.99"}, {"eps1", "1e-2"}, {"eps2", "1e-2"}, {"feature_omega_beta", "1.0"}, {"reward_mode", "zero"}, {"rho", "1.0"}};
    }
    if (env == "E9") {
        return {{"gamma", "0.99"}, {"m", "50"}, {"eps2", "1e-2"}, {"feature_omega_beta", "1.0"}, {"reward_mode", "zero"}, {"rho", "1.0"}};
    }
    if (env == "E10") {
        return {{"gamma", "0.99"}, {"k", "10"}, {"eps1", "1e-3"}, {"eps2", "1e-2"}, {"feature_omega_beta", "1.0"}, {"reward_mode", "cluster-opposite"}, {"rho", "1.0"}};
    }
    throw std::runtime_error("Unknown environment id: " + env_id);
}

static SweepMap default_environment_sweeps(const std::string &env_id) {
    const std::string env = canonical_env_id(env_id);
    SweepMap out;
    if (env == "toyexample" || env == "E4" || env == "E5" || env == "E6" || env == "E7") {
        out["feature_omega_beta"] = {"1e-3", "1e-2", "1e-1", "1.0"};
    } else {
        out["eps2"] = {"1e-4", "1e-2", "1e-1", "1.0"};
    }
    return out;
}

static std::string get_string_param(const ParamMap &params, const std::string &key, const std::string &def) {
    const auto it = params.find(key);
    return (it == params.end()) ? def : it->second;
}

static double get_float_param(const ParamMap &params, const std::string &key, const double def) {
    const auto it = params.find(key);
    if (it == params.end()) {
        return def;
    }
    return parse_double(it->second);
}

static int get_int_param(const ParamMap &params, const std::string &key, const int def) {
    const auto it = params.find(key);
    if (it == params.end()) {
        return def;
    }
    return parse_int(it->second);
}

static ParamMap merge_params(ParamMap defaults, const ParamMap &overrides) {
    for (const auto &kv : overrides) {
        defaults[kv.first] = kv.second;
    }
    return defaults;
}

static ParamMap format_metadata(const ParamMap &params, const std::vector<std::string> &keys) {
    ParamMap out;
    for (const auto &k : keys) {
        const auto it = params.find(k);
        if (it != params.end()) {
            out[k] = it->second;
        }
    }
    return out;
}

static std::string serialize_metadata(const ParamMap &metadata) {
    std::ostringstream oss;
    bool first = true;
    for (const auto &kv : metadata) {
        if (!first) {
            oss << ';';
        }
        first = false;
        oss << kv.first << '=' << kv.second;
    }
    return oss.str();
}

struct FiniteTDEnv {
    std::string env_id;
    std::string display_name;
    double gamma = 0.99;
    int n_states = 0;
    int d = 0;
    std::vector<double> P;
    std::vector<double> P_cdf;
    std::vector<double> D;
    std::vector<double> Phi;
    std::vector<double> theta_star;
    std::vector<double> V_star;
    std::vector<double> r;
    int start_state = 0;
    ParamMap metadata;
    double phi_max_sq = 0.0;
    double r_max = 0.0;
    double tau_proxy = std::numeric_limits<double>::quiet_NaN();
};

static void normalize_rows(std::vector<double> &P, const int n) {
    for (int i = 0; i < n; ++i) {
        double s = 0.0;
        for (int j = 0; j < n; ++j) {
            s += P[idx2(i, j, n)];
        }
        if (s <= 0.0) {
            throw std::runtime_error("Transition row has non-positive mass");
        }
        for (int j = 0; j < n; ++j) {
            P[idx2(i, j, n)] /= s;
        }
    }
}

static void apply_feature_omega_beta(std::vector<double> &Phi, const int n, const int d, const double beta) {
    if (d <= 1) {
        return;
    }
    if (!(beta > 0.0) || !std::isfinite(beta)) {
        throw std::runtime_error("feature_omega_beta must be positive and finite");
    }
    for (int s = 0; s < n; ++s) {
        for (int j = 1; j < d; ++j) {
            Phi[idx2(s, j, d)] *= beta;
        }
    }
}

static double normalize_phi_infty_sq(std::vector<double> &Phi, const int n, const int d) {
    double max_row_sq = 0.0;
    for (int s = 0; s < n; ++s) {
        double row_sq = 0.0;
        for (int j = 0; j < d; ++j) {
            const double v = Phi[idx2(s, j, d)];
            row_sq += v * v;
        }
        max_row_sq = std::max(max_row_sq, row_sq);
    }
    if (!(max_row_sq > 0.0) || !std::isfinite(max_row_sq)) {
        throw std::runtime_error("Feature matrix has invalid row norm for normalization");
    }
    const double scale = 1.0 / std::sqrt(max_row_sq);
    for (double &v : Phi) {
        v *= scale;
    }
    return scale;
}

static std::vector<double> stationary_distribution(const std::vector<double> &P, const int n) {
    std::vector<double> x(static_cast<size_t>(n), 1.0 / static_cast<double>(n));
    std::vector<double> xn(static_cast<size_t>(n), 0.0);
    for (int it = 0; it < 200000; ++it) {
        std::fill(xn.begin(), xn.end(), 0.0);
        for (int i = 0; i < n; ++i) {
            const double xi = x[static_cast<size_t>(i)];
            const int row_off = i * n;
            for (int j = 0; j < n; ++j) {
                xn[static_cast<size_t>(j)] += xi * P[static_cast<size_t>(row_off + j)];
            }
        }
        double sum = std::accumulate(xn.begin(), xn.end(), 0.0);
        if (sum <= 0.0 || !std::isfinite(sum)) {
            break;
        }
        for (double &v : xn) {
            v /= sum;
        }
        double diff = 0.0;
        for (int j = 0; j < n; ++j) {
            diff += std::abs(xn[static_cast<size_t>(j)] - x[static_cast<size_t>(j)]);
        }
        x.swap(xn);
        if (diff < 1e-14) {
            break;
        }
    }
    return x;
}

static bool solve_linear_system(std::vector<double> A, std::vector<double> b, std::vector<double> &x, const int n) {
    x.assign(static_cast<size_t>(n), 0.0);
    for (int col = 0; col < n; ++col) {
        int pivot = col;
        double best = std::abs(A[idx2(col, col, n)]);
        for (int r = col + 1; r < n; ++r) {
            double cand = std::abs(A[idx2(r, col, n)]);
            if (cand > best) {
                best = cand;
                pivot = r;
            }
        }
        if (best < 1e-14 || !std::isfinite(best)) {
            return false;
        }
        if (pivot != col) {
            for (int c = col; c < n; ++c) {
                std::swap(A[idx2(col, c, n)], A[idx2(pivot, c, n)]);
            }
            std::swap(b[static_cast<size_t>(col)], b[static_cast<size_t>(pivot)]);
        }

        const double diag = A[idx2(col, col, n)];
        for (int c = col; c < n; ++c) {
            A[idx2(col, c, n)] /= diag;
        }
        b[static_cast<size_t>(col)] /= diag;

        for (int r = col + 1; r < n; ++r) {
            const double f = A[idx2(r, col, n)];
            if (std::abs(f) < 1e-20) {
                continue;
            }
            for (int c = col; c < n; ++c) {
                A[idx2(r, c, n)] -= f * A[idx2(col, c, n)];
            }
            b[static_cast<size_t>(r)] -= f * b[static_cast<size_t>(col)];
        }
    }

    for (int i = n - 1; i >= 0; --i) {
        double val = b[static_cast<size_t>(i)];
        for (int c = i + 1; c < n; ++c) {
            val -= A[idx2(i, c, n)] * x[static_cast<size_t>(c)];
        }
        x[static_cast<size_t>(i)] = val;
    }
    return true;
}

static std::vector<double> safe_theta_star(const std::vector<double> &A, const std::vector<double> &b, const int d) {
    std::vector<double> x;
    if (solve_linear_system(A, b, x, d)) {
        return x;
    }

    const double avg_diag = [&]() {
        double s = 0.0;
        for (int i = 0; i < d; ++i) {
            s += std::abs(A[idx2(i, i, d)]);
        }
        return std::max(1.0, s / std::max(1, d));
    }();

    std::vector<double> Ar = A;
    double ridge = 1e-12 * avg_diag;
    for (int trial = 0; trial < 8; ++trial) {
        for (int i = 0; i < d; ++i) {
            Ar[idx2(i, i, d)] = A[idx2(i, i, d)] + ridge;
        }
        if (solve_linear_system(Ar, b, x, d)) {
            return x;
        }
        ridge *= 10.0;
    }

    throw std::runtime_error("Failed to solve theta* linear system");
}

static std::vector<double> state_reward_matrix(const std::vector<double> &r_state) {
    const int n = static_cast<int>(r_state.size());
    std::vector<double> out(static_cast<size_t>(n) * static_cast<size_t>(n), 0.0);
    for (int i = 0; i < n; ++i) {
        for (int j = 0; j < n; ++j) {
            out[idx2(i, j, n)] = r_state[static_cast<size_t>(i)];
        }
    }
    return out;
}

static std::vector<double> alternate_transition_matrix(const double eps1) {
    return {
        eps1, 1.0 - eps1,
        1.0 - eps1, eps1,
    };
}

static std::vector<double> sticky_transition_matrix(const double eps1) {
    return {
        1.0 - eps1, eps1,
        eps1, 1.0 - eps1,
    };
}

static std::vector<double> ring_transition_matrix(const int m, const double eps1) {
    std::vector<double> P(static_cast<size_t>(m) * static_cast<size_t>(m), 0.0);
    for (int i = 0; i < m; ++i) {
        P[idx2(i, i, m)] = eps1;
        P[idx2(i, (i + 1) % m, m)] = 1.0 - eps1;
    }
    return P;
}

static std::vector<double> conveyor_transition_matrix(const int m, const double eps1) {
    const int n_states = m + 1;
    std::vector<double> P(static_cast<size_t>(n_states) * static_cast<size_t>(n_states), 0.0);
    P[idx2(0, 0, n_states)] = 1.0 - eps1;
    P[idx2(0, 1, n_states)] = eps1;
    for (int i = 1; i < m; ++i) {
        P[idx2(i, i + 1, n_states)] = 1.0;
    }
    P[idx2(n_states - 1, 0, n_states)] = 1.0;
    return P;
}

static std::vector<double> reflecting_corridor_transition_matrix(const int m) {
    const int n_states = m + 1;
    std::vector<double> P(static_cast<size_t>(n_states) * static_cast<size_t>(n_states), 0.0);
    P[idx2(0, 0, n_states)] = 0.75;
    P[idx2(0, 1, n_states)] = 0.25;
    for (int i = 1; i < m; ++i) {
        P[idx2(i, i - 1, n_states)] = 0.25;
        P[idx2(i, i, n_states)] = 0.50;
        P[idx2(i, i + 1, n_states)] = 0.25;
    }
    P[idx2(n_states - 1, n_states - 2, n_states)] = 0.25;
    P[idx2(n_states - 1, n_states - 1, n_states)] = 0.75;
    return P;
}

static std::vector<double> jacobi_eigenvalues_symmetric(std::vector<double> A, const int n) {
    if (n == 0) {
        return {};
    }
    const int max_iter = std::max(50, 8 * n * n);
    for (int it = 0; it < max_iter; ++it) {
        int p = 0;
        int q = 1;
        double max_off = 0.0;
        for (int i = 0; i < n; ++i) {
            for (int j = i + 1; j < n; ++j) {
                const double aij = std::abs(A[idx2(i, j, n)]);
                if (aij > max_off) {
                    max_off = aij;
                    p = i;
                    q = j;
                }
            }
        }
        if (max_off < 1e-12) {
            break;
        }

        const double app = A[idx2(p, p, n)];
        const double aqq = A[idx2(q, q, n)];
        const double apq = A[idx2(p, q, n)];

        const double phi = 0.5 * std::atan2(2.0 * apq, aqq - app);
        const double c = std::cos(phi);
        const double s = std::sin(phi);

        for (int k = 0; k < n; ++k) {
            if (k == p || k == q) {
                continue;
            }
            const double aik = A[idx2(p, k, n)];
            const double aqk = A[idx2(q, k, n)];
            const double new_aik = c * aik - s * aqk;
            const double new_aqk = s * aik + c * aqk;
            A[idx2(p, k, n)] = new_aik;
            A[idx2(k, p, n)] = new_aik;
            A[idx2(q, k, n)] = new_aqk;
            A[idx2(k, q, n)] = new_aqk;
        }

        const double new_app = c * c * app - 2.0 * s * c * apq + s * s * aqq;
        const double new_aqq = s * s * app + 2.0 * s * c * apq + c * c * aqq;
        A[idx2(p, p, n)] = new_app;
        A[idx2(q, q, n)] = new_aqq;
        A[idx2(p, q, n)] = 0.0;
        A[idx2(q, p, n)] = 0.0;
    }

    std::vector<double> eig(static_cast<size_t>(n), 0.0);
    for (int i = 0; i < n; ++i) {
        eig[static_cast<size_t>(i)] = A[idx2(i, i, n)];
    }
    return eig;
}

static double largest_eigenvalue_power_sym(const std::vector<double> &A, const int n) {
    if (n == 0) {
        return 0.0;
    }
    std::vector<double> x(static_cast<size_t>(n), 1.0 / std::sqrt(static_cast<double>(n)));
    std::vector<double> y(static_cast<size_t>(n), 0.0);

    double prev = -1.0;
    for (int it = 0; it < 3000; ++it) {
        std::fill(y.begin(), y.end(), 0.0);
        for (int i = 0; i < n; ++i) {
            const int row_off = i * n;
            double acc = 0.0;
            for (int j = 0; j < n; ++j) {
                acc += A[static_cast<size_t>(row_off + j)] * x[static_cast<size_t>(j)];
            }
            y[static_cast<size_t>(i)] = acc;
        }

        double ynorm = std::sqrt(std::inner_product(y.begin(), y.end(), y.begin(), 0.0));
        if (!(ynorm > 0.0) || !std::isfinite(ynorm)) {
            return 0.0;
        }
        for (double &v : y) {
            v /= ynorm;
        }

        double rayleigh = 0.0;
        for (int i = 0; i < n; ++i) {
            const int row_off = i * n;
            double ax_i = 0.0;
            for (int j = 0; j < n; ++j) {
                ax_i += A[static_cast<size_t>(row_off + j)] * y[static_cast<size_t>(j)];
            }
            rayleigh += y[static_cast<size_t>(i)] * ax_i;
        }

        x.swap(y);
        if (std::abs(rayleigh - prev) < 1e-13) {
            return rayleigh;
        }
        prev = rayleigh;
    }
    return std::max(0.0, prev);
}

static double tau_proxy_from_transition(const std::vector<double> &P, const std::vector<double> &D, const int n) {
    std::vector<double> B(static_cast<size_t>(n) * static_cast<size_t>(n), 0.0);
    for (int i = 0; i < n; ++i) {
        for (int j = 0; j < n; ++j) {
            B[idx2(i, j, n)] = P[idx2(i, j, n)] - D[static_cast<size_t>(j)];
        }
    }

    std::vector<double> BtB(static_cast<size_t>(n) * static_cast<size_t>(n), 0.0);
    for (int i = 0; i < n; ++i) {
        for (int j = 0; j < n; ++j) {
            double acc = 0.0;
            for (int k = 0; k < n; ++k) {
                acc += B[idx2(k, i, n)] * B[idx2(k, j, n)];
            }
            BtB[idx2(i, j, n)] = acc;
        }
    }

    const double maxeig = std::max(0.0, largest_eigenvalue_power_sym(BtB, n));
    const double sigma = std::sqrt(maxeig);
    if (!(sigma < 1.0 - 1e-12)) {
        return std::numeric_limits<double>::infinity();
    }
    return 1.0 / std::max(1e-12, 1.0 - sigma);
}

static FiniteTDEnv finalize_environment(
    const std::string &env_id,
    const std::string &display_name,
    const double gamma,
    std::vector<double> P,
    std::vector<double> Phi,
    std::vector<double> r,
    const int start_state,
    const ParamMap &metadata
) {
    const int n = static_cast<int>(std::sqrt(static_cast<double>(P.size())));
    const int d = static_cast<int>(Phi.size() / static_cast<size_t>(n));

    normalize_rows(P, n);
    normalize_phi_infty_sq(Phi, n, d);
    std::vector<double> D = stationary_distribution(P, n);

    std::vector<double> r_bar(static_cast<size_t>(n), 0.0);
    for (int i = 0; i < n; ++i) {
        double acc = 0.0;
        const int row_off = i * n;
        for (int j = 0; j < n; ++j) {
            acc += P[static_cast<size_t>(row_off + j)] * r[static_cast<size_t>(row_off + j)];
        }
        r_bar[static_cast<size_t>(i)] = acc;
    }

    std::vector<double> A(static_cast<size_t>(d) * static_cast<size_t>(d), 0.0);
    std::vector<double> b(static_cast<size_t>(d), 0.0);

    for (int i = 0; i < d; ++i) {
        for (int j = 0; j < d; ++j) {
            double acc = 0.0;
            for (int s = 0; s < n; ++s) {
                for (int sp = 0; sp < n; ++sp) {
                    const double M_ssp = (s == sp ? 1.0 : 0.0) - gamma * P[idx2(s, sp, n)];
                    acc += Phi[idx2(s, i, d)] * D[static_cast<size_t>(s)] * M_ssp * Phi[idx2(sp, j, d)];
                }
            }
            A[idx2(i, j, d)] = acc;
        }
    }

    for (int i = 0; i < d; ++i) {
        double acc = 0.0;
        for (int s = 0; s < n; ++s) {
            acc += Phi[idx2(s, i, d)] * D[static_cast<size_t>(s)] * r_bar[static_cast<size_t>(s)];
        }
        b[static_cast<size_t>(i)] = acc;
    }

    std::vector<double> theta_star = safe_theta_star(A, b, d);
    std::vector<double> V_star(static_cast<size_t>(n), 0.0);
    for (int s = 0; s < n; ++s) {
        double acc = 0.0;
        for (int j = 0; j < d; ++j) {
            acc += Phi[idx2(s, j, d)] * theta_star[static_cast<size_t>(j)];
        }
        V_star[static_cast<size_t>(s)] = acc;
    }

    double phi_max_sq = 0.0;
    for (int s = 0; s < n; ++s) {
        double acc = 0.0;
        for (int j = 0; j < d; ++j) {
            const double v = Phi[idx2(s, j, d)];
            acc += v * v;
        }
        phi_max_sq = std::max(phi_max_sq, acc);
    }

    double r_max = 0.0;
    for (const double val : r) {
        r_max = std::max(r_max, std::abs(val));
    }

    std::vector<double> P_cdf(P.size(), 0.0);
    for (int i = 0; i < n; ++i) {
        double csum = 0.0;
        for (int j = 0; j < n; ++j) {
            csum += P[idx2(i, j, n)];
            P_cdf[idx2(i, j, n)] = csum;
        }
        P_cdf[idx2(i, n - 1, n)] = 1.0;
    }

    FiniteTDEnv env;
    env.env_id = env_id;
    env.display_name = display_name;
    env.gamma = gamma;
    env.n_states = n;
    env.d = d;
    env.P = std::move(P);
    env.P_cdf = std::move(P_cdf);
    env.D = std::move(D);
    env.Phi = std::move(Phi);
    env.theta_star = std::move(theta_star);
    env.V_star = std::move(V_star);
    env.r = std::move(r);
    env.start_state = start_state;
    env.metadata = metadata;
    env.phi_max_sq = phi_max_sq;
    env.r_max = r_max;
    env.tau_proxy = tau_proxy_from_transition(env.P, env.D, env.n_states);
    return env;
}

static FiniteTDEnv build_toyexample(const ParamMap &params) {
    const double gamma = get_float_param(params, "gamma", 0.99);
    const int seed = get_int_param(params, "seed", 114514);
    const double scale_factor = get_float_param(params, "scale_factor", 1.0);
    const double feature_omega_beta = get_float_param(params, "feature_omega_beta", 1.0);
    const int n_states = 50;
    const int d = 5;

    SplitMix64Rng reward_rng(static_cast<uint64_t>(seed));
    SplitMix64Rng feature_rng(static_cast<uint64_t>(seed));

    std::vector<double> P(static_cast<size_t>(n_states) * static_cast<size_t>(n_states), 0.0);
    for (int i = 0; i < n_states; ++i) {
        P[idx2(i, i, n_states)] = 0.1;
        P[idx2(i, (i + 1) % n_states, n_states)] = 0.6;
        P[idx2(i, (i - 1 + n_states) % n_states, n_states)] = 0.3;
    }

    std::vector<double> r(static_cast<size_t>(n_states) * static_cast<size_t>(n_states), 0.0);
    for (int i = 0; i < n_states; ++i) {
        for (int j = 0; j < n_states; ++j) {
            r[idx2(i, j, n_states)] = reward_rng.next_unit();
        }
    }

    std::vector<double> Phi(static_cast<size_t>(n_states) * static_cast<size_t>(d), 0.0);
    for (int i = 0; i < n_states; ++i) {
        for (int j = 0; j < d; ++j) {
            Phi[idx2(i, j, d)] = 10.0 * feature_rng.next_unit();
        }
    }
    if (scale_factor <= 1.0) {
        for (int i = 0; i < n_states; ++i) {
            Phi[idx2(i, 0, d)] *= scale_factor;
        }
    } else {
        for (double &v : Phi) {
            v *= scale_factor;
        }
    }
    apply_feature_omega_beta(Phi, n_states, d, feature_omega_beta);

    const ParamMap metadata = format_metadata(params, {"gamma", "seed", "scale_factor", "feature_omega_beta"});
    return finalize_environment("toyexample", "ToyExample MDP", gamma, std::move(P), std::move(Phi), std::move(r), 0, metadata);
}

static FiniteTDEnv build_e1(const ParamMap &params) {
    const double gamma = get_float_param(params, "gamma", 0.99);
    const double eps1 = get_float_param(params, "eps1", 1e-3);
    const double eps2 = get_float_param(params, "eps2", 1e-2);
    const double rho = get_float_param(params, "rho", 1.0);
    const std::string reward_mode = get_string_param(params, "reward_mode", "zero");

    std::vector<double> P = alternate_transition_matrix(eps1);
    const double cphi = std::sqrt(1.0 + eps2 * eps2);
    std::vector<double> Phi = {eps2 / cphi, 1.0 / cphi};
    std::vector<double> rewards = {0.0, reward_mode == "driven" ? rho : 0.0};

    const ParamMap metadata = format_metadata(params, {"gamma", "eps1", "eps2", "rho", "reward_mode"});
    return finalize_environment("E1", "E1 alternating scalar", gamma, std::move(P), std::move(Phi), state_reward_matrix(rewards), 0, metadata);
}

static FiniteTDEnv build_e2(const ParamMap &params) {
    const double gamma = get_float_param(params, "gamma", 0.99);
    const double eps1 = get_float_param(params, "eps1", 1e-3);
    const double eps2 = get_float_param(params, "eps2", 1e-2);
    const double feature_omega_beta = get_float_param(params, "feature_omega_beta", 1.0);
    const double rho = get_float_param(params, "rho", 1.0);
    const std::string reward_mode = get_string_param(params, "reward_mode", "zero");

    std::vector<double> P = sticky_transition_matrix(eps1);
    const double cphi = std::sqrt(2.0 + eps2 * eps2);
    std::vector<double> Phi = {
        1.0 / cphi, 0.0,
        1.0 / cphi, eps2 / cphi,
    };
    apply_feature_omega_beta(Phi, 2, 2, feature_omega_beta);
    std::vector<double> rewards = {0.0, reward_mode == "driven" ? rho : 0.0};

    const ParamMap metadata = format_metadata(params, {"gamma", "eps1", "eps2", "feature_omega_beta", "rho", "reward_mode"});
    return finalize_environment("E2", "E2 sticky two-state block", gamma, std::move(P), std::move(Phi), state_reward_matrix(rewards), 0, metadata);
}

static FiniteTDEnv build_e4(const ParamMap &params) {
    const double gamma = get_float_param(params, "gamma", 0.99);
    const double eps1 = get_float_param(params, "eps1", 1e-3);
    const double eps2 = get_float_param(params, "eps2", 1e-2);
    const double feature_omega_beta = get_float_param(params, "feature_omega_beta", 1.0);
    const double rho = get_float_param(params, "rho", 1.0);
    const std::string reward_mode = get_string_param(params, "reward_mode", "zero");

    std::vector<double> P = {
        0.0, 1.0, 0.0,
        1.0 - eps1, 0.0, eps1,
        eps1, 0.0, 1.0 - eps1,
    };
    const double cphi = std::sqrt(2.0 + eps2 * eps2);
    std::vector<double> Phi = {
        1.0 / cphi, 0.0,
        1.0 / cphi, eps2 / cphi,
        0.0, 0.0,
    };
    apply_feature_omega_beta(Phi, 3, 2, feature_omega_beta);

    std::vector<double> rewards = {0.0, 0.0, 0.0};
    if (reward_mode == "weak") {
        rewards = {0.0, rho, 0.0};
    } else if (reward_mode == "signed") {
        rewards = {0.0, rho, -rho};
    }

    const ParamMap metadata = format_metadata(params, {"gamma", "eps1", "eps2", "feature_omega_beta", "rho", "reward_mode"});
    return finalize_environment("E4", "E4 metastable trap", gamma, std::move(P), std::move(Phi), state_reward_matrix(rewards), 0, metadata);
}

static FiniteTDEnv build_e5(const ParamMap &params) {
    const double gamma = get_float_param(params, "gamma", 0.99);
    const int m = get_int_param(params, "m", 20);
    const double eps1 = get_float_param(params, "eps1", 1e-2);
    const double feature_omega_beta = get_float_param(params, "feature_omega_beta", 1.0);
    const double rho = get_float_param(params, "rho", 1.0);
    const std::string reward_mode = get_string_param(params, "reward_mode", "zero");

    std::vector<double> P = ring_transition_matrix(m, eps1);
    std::vector<double> Phi(static_cast<size_t>(m) * static_cast<size_t>(m), 0.0);
    for (int i = 0; i < m; ++i) {
        Phi[idx2(i, i, m)] = 1.0;
    }
    apply_feature_omega_beta(Phi, m, m, feature_omega_beta);

    std::vector<double> rewards(static_cast<size_t>(m), 0.0);
    if (reward_mode == "single-site") {
        rewards[0] = rho;
    } else if (reward_mode == "alternating") {
        for (int i = 0; i < m; ++i) {
            rewards[static_cast<size_t>(i)] = (i % 2 == 0) ? -rho : rho;
        }
    }

    const ParamMap metadata = format_metadata(params, {"gamma", "m", "eps1", "feature_omega_beta", "rho", "reward_mode"});
    return finalize_environment("E5", "E5 cycle transport", gamma, std::move(P), std::move(Phi), state_reward_matrix(rewards), 0, metadata);
}

static FiniteTDEnv build_e6(const ParamMap &params) {
    const double gamma = get_float_param(params, "gamma", 0.99);
    const int m = get_int_param(params, "m", 20);
    const double eps1 = get_float_param(params, "eps1", 1e-2);
    const double feature_omega_beta = get_float_param(params, "feature_omega_beta", 1.0);
    const double rho = get_float_param(params, "rho", 1.0);
    const std::string reward_mode = get_string_param(params, "reward_mode", "zero");

    std::vector<double> P = conveyor_transition_matrix(m, eps1);
    const int n_states = m + 1;

    std::vector<double> Phi(static_cast<size_t>(n_states) * static_cast<size_t>(m), 0.0);
    for (int i = 0; i < m; ++i) {
        Phi[idx2(i + 1, i, m)] = 1.0;
    }
    apply_feature_omega_beta(Phi, n_states, m, feature_omega_beta);

    std::vector<double> rewards(static_cast<size_t>(n_states), 0.0);
    if (reward_mode == "launch") {
        rewards[1] = rho;
    } else if (reward_mode == "excursion") {
        for (int i = 1; i < n_states; ++i) {
            rewards[static_cast<size_t>(i)] = rho;
        }
    }

    const ParamMap metadata = format_metadata(params, {"gamma", "m", "eps1", "feature_omega_beta", "rho", "reward_mode"});
    return finalize_environment("E6", "E6 conveyor with reset", gamma, std::move(P), std::move(Phi), state_reward_matrix(rewards), 0, metadata);
}

static FiniteTDEnv build_e8(const ParamMap &params) {
    const double gamma = get_float_param(params, "gamma", 0.99);
    const int m = get_int_param(params, "m", 32);
    const double eps1 = get_float_param(params, "eps1", 1e-2);
    const double feature_omega_beta = get_float_param(params, "feature_omega_beta", 1.0);
    const double rho = get_float_param(params, "rho", 1.0);
    const std::string reward_mode = get_string_param(params, "reward_mode", "zero");

    std::vector<double> P = ring_transition_matrix(m, eps1);
    std::vector<double> Phi(static_cast<size_t>(m) * 2ULL, 0.0);
    for (int i = 0; i < m; ++i) {
        const double alpha = 2.0 * kPi * static_cast<double>(i) / static_cast<double>(m);
        Phi[idx2(i, 0, 2)] = std::cos(alpha) / std::sqrt(static_cast<double>(m));
        Phi[idx2(i, 1, 2)] = std::sin(alpha) / std::sqrt(static_cast<double>(m));
    }
    apply_feature_omega_beta(Phi, m, 2, feature_omega_beta);

    std::vector<double> rewards(static_cast<size_t>(m), 0.0);
    if (reward_mode == "single-harmonic") {
        for (int i = 0; i < m; ++i) {
            const double alpha = 2.0 * kPi * static_cast<double>(i) / static_cast<double>(m);
            rewards[static_cast<size_t>(i)] = rho * std::cos(alpha);
        }
    } else if (reward_mode == "phase-shifted") {
        for (int i = 0; i < m; ++i) {
            const double alpha = 2.0 * kPi * static_cast<double>(i) / static_cast<double>(m);
            rewards[static_cast<size_t>(i)] = rho * std::sin(alpha);
        }
    }

    const ParamMap metadata = format_metadata(params, {"gamma", "m", "eps1", "feature_omega_beta", "rho", "reward_mode"});
    return finalize_environment("E8", "E8 rotating-arc ring", gamma, std::move(P), std::move(Phi), state_reward_matrix(rewards), 0, metadata);
}

static FiniteTDEnv build_e9(const ParamMap &params) {
    const double gamma = get_float_param(params, "gamma", 0.99);
    const int m = get_int_param(params, "m", 64);
    const double eps1 = get_float_param(params, "eps1", 1e-2);
    const double alpha_max = get_float_param(params, "alpha_max", kPi / 2.0);
    const double feature_omega_beta = get_float_param(params, "feature_omega_beta", 1.0);
    const double rho = get_float_param(params, "rho", 1.0);
    const std::string reward_mode = get_string_param(params, "reward_mode", "zero");

    const int n_states = m + 1;
    std::vector<double> P(static_cast<size_t>(n_states) * static_cast<size_t>(n_states), 0.0);
    P[idx2(0, 1, n_states)] = 1.0;
    for (int i = 1; i < m; ++i) {
        P[idx2(i, i + 1, n_states)] = 1.0 - eps1;
        P[idx2(i, 0, n_states)] = eps1;
    }
    P[idx2(n_states - 1, 0, n_states)] = 1.0;

    std::vector<double> Phi(static_cast<size_t>(n_states) * 2ULL, 0.0);
    for (int i = 0; i < m; ++i) {
        const double alpha = alpha_max * static_cast<double>(i + 1) / static_cast<double>(m);
        Phi[idx2(i + 1, 0, 2)] = std::cos(alpha) / std::sqrt(static_cast<double>(m));
        Phi[idx2(i + 1, 1, 2)] = std::sin(alpha) / std::sqrt(static_cast<double>(m));
    }
    apply_feature_omega_beta(Phi, n_states, 2, feature_omega_beta);

    std::vector<double> rewards(static_cast<size_t>(n_states), 0.0);
    if (reward_mode == "uniform") {
        for (int i = 1; i < n_states; ++i) {
            rewards[static_cast<size_t>(i)] = rho;
        }
    } else if (reward_mode == "late-excursion") {
        const int start_idx = 1 + (m + 1) / 2;
        for (int i = start_idx; i < n_states; ++i) {
            rewards[static_cast<size_t>(i)] = rho;
        }
    }

    const ParamMap metadata = format_metadata(params, {"gamma", "m", "eps1", "alpha_max", "feature_omega_beta", "rho", "reward_mode"});
    return finalize_environment("E9", "E9 open excursion arc", gamma, std::move(P), std::move(Phi), state_reward_matrix(rewards), 0, metadata);
}

static FiniteTDEnv build_e10(const ParamMap &params) {
    const double gamma = get_float_param(params, "gamma", 0.99);
    const double eps1 = get_float_param(params, "eps1", 1e-2);
    const double eps2 = get_float_param(params, "eps2", 1e-2);
    const double feature_omega_beta = get_float_param(params, "feature_omega_beta", 1.0);
    const double rho = get_float_param(params, "rho", 1.0);
    const std::string reward_mode = get_string_param(params, "reward_mode", "zero");

    std::vector<double> P = ring_transition_matrix(4, eps1);
    const double scale = 1.0 / std::sqrt(3.0);
    std::vector<double> Phi = {
        1.0 * scale, 0.0,
        1.0 * scale, eps2 * scale,
        0.0, 1.0 * scale,
        -1.0 * scale, eps2 * scale,
    };
    apply_feature_omega_beta(Phi, 4, 2, feature_omega_beta);
    std::vector<double> rewards = {0.0, 0.0, 0.0, 0.0};
    if (reward_mode == "signed-cycle") {
        rewards = {0.0, rho, 0.0, -rho};
    }

    const ParamMap metadata = format_metadata(params, {"gamma", "eps1", "eps2", "feature_omega_beta", "rho", "reward_mode"});
    return finalize_environment("E10", "E10 bow-tie cycle", gamma, std::move(P), std::move(Phi), state_reward_matrix(rewards), 0, metadata);
}

static FiniteTDEnv build_e11(const ParamMap &params) {
    const double gamma = get_float_param(params, "gamma", 0.99);
    const int m = get_int_param(params, "m", 50);
    const double eps2 = get_float_param(params, "eps2", 1e-2);
    const double feature_omega_beta = get_float_param(params, "feature_omega_beta", 1.0);
    const double rho = get_float_param(params, "rho", 1.0);
    const std::string reward_mode = get_string_param(params, "reward_mode", "zero");

    std::vector<double> P = reflecting_corridor_transition_matrix(m);
    const int n_states = m + 1;

    std::vector<double> Phi(static_cast<size_t>(n_states) * 2ULL, 0.0);
    const double cphi = std::sqrt((m + 1.0) * (1.0 + eps2 * eps2));
    for (int i = 0; i <= m; ++i) {
        const double slope = eps2 * (2.0 * static_cast<double>(i) - static_cast<double>(m)) / static_cast<double>(m);
        Phi[idx2(i, 0, 2)] = 1.0 / cphi;
        Phi[idx2(i, 1, 2)] = slope / cphi;
    }
    apply_feature_omega_beta(Phi, n_states, 2, feature_omega_beta);

    std::vector<double> rewards(static_cast<size_t>(n_states), 0.0);
    if (reward_mode == "linear") {
        for (int i = 0; i <= m; ++i) {
            rewards[static_cast<size_t>(i)] = rho * (2.0 * static_cast<double>(i) - static_cast<double>(m)) / static_cast<double>(m);
        }
    } else if (reward_mode == "half-space") {
        for (int i = 0; i <= m; ++i) {
            const double x = 2.0 * static_cast<double>(i) - static_cast<double>(m);
            rewards[static_cast<size_t>(i)] = x > 0.0 ? rho : (x < 0.0 ? -rho : 0.0);
        }
    }

    const ParamMap metadata = format_metadata(params, {"gamma", "m", "eps2", "feature_omega_beta", "rho", "reward_mode"});
    return finalize_environment("E11", "E11 diffusive corridor", gamma, std::move(P), std::move(Phi), state_reward_matrix(rewards), 0, metadata);
}

static FiniteTDEnv build_e12(const ParamMap &params) {
    const double gamma = get_float_param(params, "gamma", 0.99);
    const int k = get_int_param(params, "k", 10);
    const double eps1 = get_float_param(params, "eps1", 1e-3);
    const double eps2 = get_float_param(params, "eps2", 1e-2);
    const double feature_omega_beta = get_float_param(params, "feature_omega_beta", 1.0);
    const double rho = get_float_param(params, "rho", 1.0);
    const std::string reward_mode = get_string_param(params, "reward_mode", "cluster-opposite");

    const int n_states = 2 * k;
    std::vector<double> P(static_cast<size_t>(n_states) * static_cast<size_t>(n_states), 0.0);
    for (int i = 0; i < k; ++i) {
        for (int j = 0; j < k; ++j) {
            P[idx2(i, j, n_states)] = (1.0 - eps1) / static_cast<double>(k);
        }
        for (int j = k; j < n_states; ++j) {
            P[idx2(i, j, n_states)] = eps1 / static_cast<double>(k);
        }
    }
    for (int i = k; i < n_states; ++i) {
        for (int j = 0; j < k; ++j) {
            P[idx2(i, j, n_states)] = eps1 / static_cast<double>(k);
        }
        for (int j = k; j < n_states; ++j) {
            P[idx2(i, j, n_states)] = (1.0 - eps1) / static_cast<double>(k);
        }
    }

    std::vector<double> Phi(static_cast<size_t>(n_states) * 2ULL, 0.0);
    const double cphi = std::sqrt(2.0 * static_cast<double>(k));
    for (int i = 0; i < k; ++i) {
        Phi[idx2(i, 0, 2)] = 1.0 / cphi;
        Phi[idx2(i, 1, 2)] = eps2 / cphi;
    }
    for (int i = k; i < n_states; ++i) {
        Phi[idx2(i, 0, 2)] = 1.0 / cphi;
        Phi[idx2(i, 1, 2)] = -eps2 / cphi;
    }
    apply_feature_omega_beta(Phi, n_states, 2, feature_omega_beta);

    std::vector<double> rewards(static_cast<size_t>(n_states), rho);
    if (reward_mode == "cluster-opposite") {
        for (int i = k; i < n_states; ++i) {
            rewards[static_cast<size_t>(i)] = -rho;
        }
    }

    const ParamMap metadata = format_metadata(params, {"gamma", "k", "eps1", "eps2", "feature_omega_beta", "rho", "reward_mode"});
    return finalize_environment("E12", "E12 two-cluster forcing", gamma, std::move(P), std::move(Phi), state_reward_matrix(rewards), 0, metadata);
}

static FiniteTDEnv relabel_environment(FiniteTDEnv env, const std::string &new_env_id, const std::string &new_display_name) {
    env.env_id = new_env_id;
    env.display_name = new_display_name;
    return env;
}

static FiniteTDEnv build_environment(const std::string &env_id, const ParamMap &params) {
    const std::string env = canonical_env_id(env_id);
    const ParamMap merged = merge_params(default_environment_params(env), params);

    if (env == "toyexample") return build_toyexample(merged);
    if (env == "E1") return build_e1(merged);
    if (env == "E2") return build_e2(merged);
    if (env == "E3") return relabel_environment(build_e4(merged), "E3", "E3 metastable trap");
    if (env == "E4") return relabel_environment(build_e5(merged), "E4", "E4 cycle transport");
    if (env == "E5") return relabel_environment(build_e6(merged), "E5", "E5 conveyor with reset");
    if (env == "E6") return relabel_environment(build_e8(merged), "E6", "E6 rotating-arc ring");
    if (env == "E7") return relabel_environment(build_e9(merged), "E7", "E7 open excursion arc");
    if (env == "E8") return relabel_environment(build_e10(merged), "E8", "E8 bow-tie cycle");
    if (env == "E9") return relabel_environment(build_e11(merged), "E9", "E9 diffusive corridor");
    if (env == "E10") return relabel_environment(build_e12(merged), "E10", "E10 two-cluster forcing");

    throw std::runtime_error("Unknown environment id: " + env_id);
}

struct ObjectiveMatrices {
    std::vector<double> G;
    std::vector<double> b;
    double c = 0.0;

    std::vector<double> G_A;
    std::vector<double> b_A;
    double c_A = 0.0;

    double omega = std::numeric_limits<double>::quiet_NaN();
    double kappa = std::numeric_limits<double>::quiet_NaN();
    double lambda_sym = std::numeric_limits<double>::quiet_NaN();  // min eig((A+A^T)/2), A = Phi^T D (I-gamma P) Phi
    double theta_star_sq = 0.0;
};

static ObjectiveMatrices compute_objective_matrices(const FiniteTDEnv &env) {
    const int n = env.n_states;
    const int d = env.d;

    std::vector<double> A1_diag(static_cast<size_t>(n), 0.0);
    for (int i = 0; i < n; ++i) {
        A1_diag[static_cast<size_t>(i)] = (1.0 - env.gamma) * env.D[static_cast<size_t>(i)];
    }

    std::vector<double> S(static_cast<size_t>(n) * static_cast<size_t>(n), 0.0);
    for (int i = 0; i < n; ++i) {
        for (int j = 0; j < n; ++j) {
            const double d_i = env.D[static_cast<size_t>(i)];
            const double d_j = env.D[static_cast<size_t>(j)];
            const double dij = (i == j) ? d_i : 0.0;
            const double dp = d_i * env.P[idx2(i, j, n)];
            const double ptd = env.P[idx2(j, i, n)] * d_j;
            S[idx2(i, j, n)] = dij - 0.5 * (dp + ptd);
        }
    }

    std::vector<double> A2(static_cast<size_t>(n) * static_cast<size_t>(n), 0.0);
    for (int i = 0; i < n; ++i) {
        for (int j = 0; j < n; ++j) {
            const double a1 = (i == j) ? A1_diag[static_cast<size_t>(i)] : 0.0;
            A2[idx2(i, j, n)] = a1 + env.gamma * S[idx2(i, j, n)];
        }
    }

    ObjectiveMatrices m;
    m.G.assign(static_cast<size_t>(d) * static_cast<size_t>(d), 0.0);
    m.b.assign(static_cast<size_t>(d), 0.0);
    m.G_A.assign(static_cast<size_t>(d) * static_cast<size_t>(d), 0.0);
    m.b_A.assign(static_cast<size_t>(d), 0.0);

    for (int i = 0; i < d; ++i) {
        for (int j = 0; j < d; ++j) {
            double acc = 0.0;
            for (int s = 0; s < n; ++s) {
                acc += env.Phi[idx2(s, i, d)] * A1_diag[static_cast<size_t>(s)] * env.Phi[idx2(s, j, d)];
            }
            m.G[idx2(i, j, d)] = acc;
        }
    }

    for (int i = 0; i < d; ++i) {
        double acc = 0.0;
        for (int s = 0; s < n; ++s) {
            acc += env.Phi[idx2(s, i, d)] * A1_diag[static_cast<size_t>(s)] * env.V_star[static_cast<size_t>(s)];
        }
        m.b[static_cast<size_t>(i)] = acc;
    }

    {
        double acc = 0.0;
        for (int s = 0; s < n; ++s) {
            acc += env.V_star[static_cast<size_t>(s)] * A1_diag[static_cast<size_t>(s)] * env.V_star[static_cast<size_t>(s)];
        }
        m.c = acc;
    }

    for (int i = 0; i < d; ++i) {
        for (int j = 0; j < d; ++j) {
            double acc = 0.0;
            for (int s = 0; s < n; ++s) {
                const double phi_si = env.Phi[idx2(s, i, d)];
                double inner = 0.0;
                for (int t = 0; t < n; ++t) {
                    inner += A2[idx2(s, t, n)] * env.Phi[idx2(t, j, d)];
                }
                acc += phi_si * inner;
            }
            m.G_A[idx2(i, j, d)] = acc;
        }
    }

    for (int i = 0; i < d; ++i) {
        double acc = 0.0;
        for (int s = 0; s < n; ++s) {
            const double phi_si = env.Phi[idx2(s, i, d)];
            double inner = 0.0;
            for (int t = 0; t < n; ++t) {
                inner += A2[idx2(s, t, n)] * env.V_star[static_cast<size_t>(t)];
            }
            acc += phi_si * inner;
        }
        m.b_A[static_cast<size_t>(i)] = acc;
    }

    {
        double acc = 0.0;
        for (int s = 0; s < n; ++s) {
            double inner = 0.0;
            for (int t = 0; t < n; ++t) {
                inner += A2[idx2(s, t, n)] * env.V_star[static_cast<size_t>(t)];
            }
            acc += env.V_star[static_cast<size_t>(s)] * inner;
        }
        m.c_A = acc;
    }

    std::vector<double> eig = jacobi_eigenvalues_symmetric(m.G, d);
    if (!eig.empty()) {
        auto [emin_it, emax_it] = std::minmax_element(eig.begin(), eig.end());
        m.omega = *emin_it;
        const double lam_max = *emax_it;
        m.kappa = (m.omega > 0.0) ? lam_max / m.omega : std::numeric_limits<double>::infinity();
    }

    // Standard TD mean matrix: A = Phi^T * D * (I - gamma P) * Phi
    std::vector<double> Bphi(static_cast<size_t>(n) * static_cast<size_t>(d), 0.0);
    for (int s = 0; s < n; ++s) {
        const double ds = env.D[static_cast<size_t>(s)];
        for (int j = 0; j < d; ++j) {
            double acc = 0.0;
            for (int t = 0; t < n; ++t) {
                const double coeff = ds * ((s == t ? 1.0 : 0.0) - env.gamma * env.P[idx2(s, t, n)]);
                acc += coeff * env.Phi[idx2(t, j, d)];
            }
            Bphi[idx2(s, j, d)] = acc;
        }
    }

    std::vector<double> A_td(static_cast<size_t>(d) * static_cast<size_t>(d), 0.0);
    for (int i = 0; i < d; ++i) {
        for (int j = 0; j < d; ++j) {
            double acc = 0.0;
            for (int s = 0; s < n; ++s) {
                acc += env.Phi[idx2(s, i, d)] * Bphi[idx2(s, j, d)];
            }
            A_td[idx2(i, j, d)] = acc;
        }
    }

    std::vector<double> sym_A(static_cast<size_t>(d) * static_cast<size_t>(d), 0.0);
    for (int i = 0; i < d; ++i) {
        for (int j = 0; j < d; ++j) {
            sym_A[idx2(i, j, d)] = 0.5 * (A_td[idx2(i, j, d)] + A_td[idx2(j, i, d)]);
        }
    }
    std::vector<double> eig_sym = jacobi_eigenvalues_symmetric(sym_A, d);
    if (!eig_sym.empty()) {
        m.lambda_sym = *std::min_element(eig_sym.begin(), eig_sym.end());
    }

    m.theta_star_sq = std::inner_product(env.theta_star.begin(), env.theta_star.end(), env.theta_star.begin(), 0.0);
    return m;
}

enum class ScheduleType {
    Theory,
    TheoryLog2,
    ConstantOmega,
    Constant,
    InvT,
    InvSqrtT,
    InvTwoThirdsT,
    InvOmegaT,
};

enum class ProjectionType {
    None,
    Oracle,
    Upper,
};

struct AlgorithmSpec {
    ScheduleType schedule = ScheduleType::Theory;
    ProjectionType projection = ProjectionType::None;
    double param = 1.0;
    std::string param_name = "c";
};

static std::string schedule_name(const ScheduleType s) {
    switch (s) {
        case ScheduleType::Theory: return "theory";
        case ScheduleType::TheoryLog2: return "theory_log2";
        case ScheduleType::ConstantOmega: return "constant_omega";
        case ScheduleType::Constant: return "constant";
        case ScheduleType::InvT: return "inv_t";
        case ScheduleType::InvSqrtT: return "inv_sqrt_t";
        case ScheduleType::InvTwoThirdsT: return "inv_t_2_3";
        case ScheduleType::InvOmegaT: return "inv_omega_t";
    }
    return "unknown";
}

static std::string projection_name(const ProjectionType p) {
    switch (p) {
        case ProjectionType::None: return "none";
        case ProjectionType::Oracle: return "oracle";
        case ProjectionType::Upper: return "upper";
    }
    return "unknown";
}

static ScheduleType parse_schedule(const std::string &token) {
    const std::string t = to_lower(trim(token));
    if (t == "theory") return ScheduleType::Theory;
    if (t == "theory_log2" || t == "theory2" || t == "theory_logsquared") return ScheduleType::TheoryLog2;
    if (t == "constant_omega" || t == "const_omega" || t == "constant=omega" || t == "omega_constant") {
        return ScheduleType::ConstantOmega;
    }
    if (t == "constant" || t == "const") return ScheduleType::Constant;
    if (t == "inv_t" || t == "1/t") return ScheduleType::InvT;
    if (t == "inv_sqrt_t" || t == "1/sqrt_t" || t == "1/sqrt(t)") return ScheduleType::InvSqrtT;
    if (t == "inv_t_2_3" || t == "inv_two_thirds_t" || t == "inv_twothirds_t" || t == "1/t_2_3" || t == "t^-2/3") {
        return ScheduleType::InvTwoThirdsT;
    }
    if (t == "inv_omega_t" || t == "1/omega_t" || t == "1/(omega*t)") return ScheduleType::InvOmegaT;
    throw std::runtime_error("Unknown schedule token: " + token);
}

static ProjectionType parse_projection(const std::string &token) {
    const std::string t = to_lower(trim(token));
    if (t == "none" || t == "unprojected") return ProjectionType::None;
    if (t == "oracle" || t == "proj_oracle") return ProjectionType::Oracle;
    if (t == "upper" || t == "proj_upper") return ProjectionType::Upper;
    throw std::runtime_error("Unknown projection token: " + token);
}

static double projection_radius(const FiniteTDEnv &env, const ObjectiveMatrices &metrics, const ProjectionType p) {
    if (p == ProjectionType::None) {
        return std::numeric_limits<double>::infinity();
    }
    if (p == ProjectionType::Oracle) {
        return std::sqrt(std::max(0.0, metrics.theta_star_sq));
    }

    const double omega = std::max(metrics.omega, 1e-12);
    const double one_minus_gamma = std::max(1e-12, 1.0 - env.gamma);
    const double denom = std::sqrt(omega) * std::pow(one_minus_gamma, 1.5);
    if (!(denom > 0.0) || !std::isfinite(denom)) {
        return std::numeric_limits<double>::infinity();
    }
    return 2.0 * env.r_max / denom;
}

static double alpha_t(
    const AlgorithmSpec &spec,
    const FiniteTDEnv &env,
    const ObjectiveMatrices &metrics,
    const int t,
    const int n_steps,
    const double t0
) {
    const double c = std::max(spec.param, 1e-16);
    switch (spec.schedule) {
        case ScheduleType::Theory: {
            const double denom = c * std::max(env.phi_max_sq, 1e-12) * std::max(std::log(static_cast<double>(n_steps)), 1.0) *
                                 std::log(static_cast<double>(t) + 3.0) * std::sqrt(static_cast<double>(t) + 1.0);
            return 1.0 / std::max(denom, 1e-16);
        }
        case ScheduleType::TheoryLog2: {
            const double log_term = std::log(static_cast<double>(t) + 3.0);
            const double denom = c * std::max(env.phi_max_sq, 1e-12) * log_term * log_term * std::sqrt(static_cast<double>(t) + 1.0);
            return 1.0 / std::max(denom, 1e-16);
        }
        case ScheduleType::ConstantOmega:
            return std::max(metrics.omega, 1e-12) / c;
        case ScheduleType::Constant:
            return 1.0 / c;
        case ScheduleType::InvT:
            return 1.0 / (c * std::max(1.0, static_cast<double>(t) + t0));
        case ScheduleType::InvSqrtT:
            return 1.0 / (c * std::sqrt(std::max(1.0, static_cast<double>(t) + t0)));
        case ScheduleType::InvTwoThirdsT:
            return 1.0 / (c * std::pow(std::max(1.0, static_cast<double>(t) + t0), 2.0 / 3.0));
        case ScheduleType::InvOmegaT: {
            const double denom = c * std::max(metrics.omega, 1e-12) * std::max(1.0, static_cast<double>(t) + t0);
            return 1.0 / std::max(denom, 1e-16);
        }
    }
    return 1.0 / c;
}

static uint64_t stable_seed(const double x, const int run_idx, const uint64_t salt = 0ULL) {
    uint64_t bits = 0;
    std::memcpy(&bits, &x, sizeof(double));
    const uint64_t b = static_cast<uint64_t>(run_idx);
    const uint64_t z = (bits * 0x9E3779B97F4A7C15ULL) ^ (b * 0xD2B74407B1CE6E93ULL) ^ salt ^ 0x94D049BB133111EBULL;
    return (z % 0x7fffffffULL) + 1ULL;
}

struct RunResult {
    int run_idx = 0;
    bool diverged = false;
    int diverged_at = -1;
    std::vector<double> vbar_errs;
    std::vector<double> vbar_errs_A;
    std::vector<double> theta_norms;
    double max_theta_norm = 0.0;
    double final_vbar = std::numeric_limits<double>::quiet_NaN();
    double final_vbar_A = std::numeric_limits<double>::quiet_NaN();
    double final_theta_norm = std::numeric_limits<double>::quiet_NaN();
    double max_alpha = 0.0;
    int proj_clip_count = 0;
};

struct AggregateResult {
    std::vector<int> timesteps;
    std::vector<double> avg_vbar;
    std::vector<double> std_vbar;
    std::vector<double> avg_vbar_A;
    std::vector<double> std_vbar_A;
    std::vector<double> avg_theta_norms;
    std::vector<double> std_theta_norms;
    std::vector<double> alpha_mean;
    std::vector<double> alpha_min;
    std::vector<double> alpha_max;
    double max_avg_theta = 0.0;
    double max_std_theta = 0.0;
    int diverged = 0;
    double divergence_rate = 0.0;
};

static std::vector<int> checkpoint_indices(const int n_steps, const int dense_prefix = 100, const double log_step_decades = 0.01) {
    if (n_steps < 1) {
        return {};
    }
    const int keep_prefix = std::min(n_steps, std::max(dense_prefix, 1));
    std::vector<int> checkpoints;
    checkpoints.reserve(static_cast<size_t>(keep_prefix + 256));
    for (int t = 1; t <= keep_prefix; ++t) {
        checkpoints.push_back(t);
    }

    const double factor = std::pow(10.0, log_step_decades);
    int last_t = keep_prefix;
    while (last_t < n_steps) {
        int next_t = std::max(last_t + 1, static_cast<int>(std::ceil(static_cast<double>(last_t) * factor)));
        next_t = std::min(next_t, n_steps);
        if (!checkpoints.empty() && next_t == checkpoints.back()) {
            break;
        }
        checkpoints.push_back(next_t);
        last_t = next_t;
    }

    if (checkpoints.empty() || checkpoints.back() != n_steps) {
        checkpoints.push_back(n_steps);
    }
    return checkpoints;
}

static std::pair<int, double> sample_step(const FiniteTDEnv &env, const int s, SplitMix64Rng &rng) {
    const double u = rng.next_unit();
    const int row_off = s * env.n_states;
    int s_next = env.n_states - 1;
    for (int j = 0; j < env.n_states; ++j) {
        if (u <= env.P_cdf[static_cast<size_t>(row_off + j)]) {
            s_next = j;
            break;
        }
    }
    const double reward = env.r[idx2(s, s_next, env.n_states)];
    return {s_next, reward};
}

static RunResult run_single_simulation(
    const AlgorithmSpec &spec,
    const int run_idx,
    const int n_steps,
    const std::vector<int> &checkpoints,
    const FiniteTDEnv &env,
    const ObjectiveMatrices &metrics,
    const double t0
) {
    SplitMix64Rng rng(stable_seed(spec.param, run_idx));

    RunResult res;
    res.run_idx = run_idx;
    const int d = env.d;

    std::vector<double> w(static_cast<size_t>(d), 0.0);
    std::vector<double> theta_bar(static_cast<size_t>(d), 0.0);

    const int n_cp = static_cast<int>(checkpoints.size());
    res.vbar_errs.assign(static_cast<size_t>(n_cp), std::numeric_limits<double>::quiet_NaN());
    res.vbar_errs_A.assign(static_cast<size_t>(n_cp), std::numeric_limits<double>::quiet_NaN());
    res.theta_norms.assign(static_cast<size_t>(n_cp), std::numeric_limits<double>::quiet_NaN());

    const double proj_R = projection_radius(env, metrics, spec.projection);
    const double proj_R2 = std::isfinite(proj_R) ? proj_R * proj_R : std::numeric_limits<double>::infinity();

    int s = env.start_state;
    int cp_idx = 0;

    for (int t = 1; t <= n_steps; ++t) {
        const auto [s_next, reward] = sample_step(env, s, rng);

        double dot_phi = 0.0;
        double dot_phi_next = 0.0;
        for (int j = 0; j < d; ++j) {
            const double wj = w[static_cast<size_t>(j)];
            dot_phi += wj * env.Phi[idx2(s, j, d)];
            dot_phi_next += wj * env.Phi[idx2(s_next, j, d)];
        }
        const double delta = reward + env.gamma * dot_phi_next - dot_phi;

        const double alpha = alpha_t(spec, env, metrics, t, n_steps, t0);
        res.max_alpha = std::max(res.max_alpha, alpha);

        for (int j = 0; j < d; ++j) {
            w[static_cast<size_t>(j)] += alpha * delta * env.Phi[idx2(s, j, d)];
        }

        if (spec.projection != ProjectionType::None && std::isfinite(proj_R) && proj_R > 0.0) {
            double n2 = std::inner_product(w.begin(), w.end(), w.begin(), 0.0);
            if (n2 > proj_R2 && std::isfinite(n2)) {
                const double nrm = std::sqrt(n2);
                const double scale = proj_R / std::max(nrm, 1e-16);
                for (double &wv : w) {
                    wv *= scale;
                }
                res.proj_clip_count += 1;
            }
        }

        const double inv_t = 1.0 / static_cast<double>(t);
        for (int j = 0; j < d; ++j) {
            const double wj = w[static_cast<size_t>(j)];
            theta_bar[static_cast<size_t>(j)] += (wj - theta_bar[static_cast<size_t>(j)]) * inv_t;
        }

        double q = 0.0;
        for (int i = 0; i < d; ++i) {
            double acc = 0.0;
            for (int j = 0; j < d; ++j) {
                acc += metrics.G[idx2(i, j, d)] * theta_bar[static_cast<size_t>(j)];
            }
            q += theta_bar[static_cast<size_t>(i)] * acc;
        }
        const double vbar = q - 2.0 * std::inner_product(theta_bar.begin(), theta_bar.end(), metrics.b.begin(), 0.0) + metrics.c;

        double qA = 0.0;
        for (int i = 0; i < d; ++i) {
            double accA = 0.0;
            for (int j = 0; j < d; ++j) {
                accA += metrics.G_A[idx2(i, j, d)] * theta_bar[static_cast<size_t>(j)];
            }
            qA += theta_bar[static_cast<size_t>(i)] * accA;
        }
        const double vbarA = qA - 2.0 * std::inner_product(theta_bar.begin(), theta_bar.end(), metrics.b_A.begin(), 0.0) + metrics.c_A;

        const double theta_n2 = std::inner_product(w.begin(), w.end(), w.begin(), 0.0);
        res.max_theta_norm = std::max(res.max_theta_norm, theta_n2);
        res.final_vbar = vbar;
        res.final_vbar_A = vbarA;
        res.final_theta_norm = theta_n2;

        while (cp_idx < n_cp && checkpoints[static_cast<size_t>(cp_idx)] == t) {
            res.vbar_errs[static_cast<size_t>(cp_idx)] = vbar;
            res.vbar_errs_A[static_cast<size_t>(cp_idx)] = vbarA;
            res.theta_norms[static_cast<size_t>(cp_idx)] = theta_n2;
            cp_idx += 1;
        }

        if (!(theta_n2 < kDivergenceThreshold) || !std::isfinite(theta_n2)) {
            res.diverged = true;
            res.diverged_at = t;
            res.final_vbar = std::numeric_limits<double>::infinity();
            res.final_vbar_A = std::numeric_limits<double>::infinity();
            res.final_theta_norm = std::numeric_limits<double>::infinity();
            while (cp_idx < n_cp) {
                res.vbar_errs[static_cast<size_t>(cp_idx)] = std::numeric_limits<double>::infinity();
                res.vbar_errs_A[static_cast<size_t>(cp_idx)] = std::numeric_limits<double>::infinity();
                res.theta_norms[static_cast<size_t>(cp_idx)] = std::numeric_limits<double>::infinity();
                cp_idx += 1;
            }
            break;
        }

        s = s_next;
    }

    return res;
}

static AggregateResult aggregate_results(
    const std::vector<RunResult> &results,
    const std::vector<int> &checkpoints,
    const AlgorithmSpec &spec,
    const FiniteTDEnv &env,
    const ObjectiveMatrices &metrics,
    const int n_steps,
    const double t0
) {
    const int n_runs = static_cast<int>(results.size());
    const int n_cp = static_cast<int>(checkpoints.size());

    AggregateResult agg;
    agg.timesteps = checkpoints;
    agg.avg_vbar.assign(static_cast<size_t>(n_cp), 0.0);
    agg.std_vbar.assign(static_cast<size_t>(n_cp), 0.0);
    agg.avg_vbar_A.assign(static_cast<size_t>(n_cp), 0.0);
    agg.std_vbar_A.assign(static_cast<size_t>(n_cp), 0.0);
    agg.avg_theta_norms.assign(static_cast<size_t>(n_cp), 0.0);
    agg.std_theta_norms.assign(static_cast<size_t>(n_cp), 0.0);
    agg.alpha_mean.assign(static_cast<size_t>(n_cp), 0.0);
    agg.alpha_min.assign(static_cast<size_t>(n_cp), 0.0);
    agg.alpha_max.assign(static_cast<size_t>(n_cp), 0.0);

    for (int cp = 0; cp < n_cp; ++cp) {
        double sv = 0.0, sv2 = 0.0;
        double sA = 0.0, sA2 = 0.0;
        double st = 0.0, st2 = 0.0;
        int cnt = 0;

        for (const auto &r : results) {
            const double v = r.vbar_errs[static_cast<size_t>(cp)];
            const double va = r.vbar_errs_A[static_cast<size_t>(cp)];
            const double th = r.theta_norms[static_cast<size_t>(cp)];
            if (!std::isfinite(v) || !std::isfinite(va) || !std::isfinite(th)) {
                continue;
            }
            sv += v;
            sv2 += v * v;
            sA += va;
            sA2 += va * va;
            st += th;
            st2 += th * th;
            cnt += 1;
        }

        const double denom = static_cast<double>(std::max(1, cnt));
        const double av = sv / denom;
        const double avA = sA / denom;
        const double at = st / denom;

        agg.avg_vbar[static_cast<size_t>(cp)] = av;
        agg.avg_vbar_A[static_cast<size_t>(cp)] = avA;
        agg.avg_theta_norms[static_cast<size_t>(cp)] = at;

        agg.std_vbar[static_cast<size_t>(cp)] = std::sqrt(std::max(0.0, sv2 / denom - av * av));
        agg.std_vbar_A[static_cast<size_t>(cp)] = std::sqrt(std::max(0.0, sA2 / denom - avA * avA));
        agg.std_theta_norms[static_cast<size_t>(cp)] = std::sqrt(std::max(0.0, st2 / denom - at * at));

        const double a = alpha_t(spec, env, metrics, checkpoints[static_cast<size_t>(cp)], n_steps, t0);
        agg.alpha_mean[static_cast<size_t>(cp)] = a;
        agg.alpha_min[static_cast<size_t>(cp)] = a;
        agg.alpha_max[static_cast<size_t>(cp)] = a;
    }

    const auto it = std::max_element(agg.avg_theta_norms.begin(), agg.avg_theta_norms.end());
    if (it != agg.avg_theta_norms.end()) {
        const size_t pos = static_cast<size_t>(it - agg.avg_theta_norms.begin());
        agg.max_avg_theta = *it;
        agg.max_std_theta = agg.std_theta_norms[pos];
    }

    agg.diverged = static_cast<int>(std::count_if(results.begin(), results.end(), [](const RunResult &r) { return r.diverged; }));
    agg.divergence_rate = static_cast<double>(agg.diverged) / static_cast<double>(std::max(1, n_runs));
    return agg;
}

struct RunnerConfig {
    std::string mode = "sweep";
    std::string env_id = "toyexample";
    int n_steps = 10'000'000;
    int n_runs = 48;
    std::string outroot = "td_cxx_logs";

    ParamMap set_params;
    SweepMap sweep_params;

    std::vector<double> base_values;
    std::vector<ScheduleType> schedules;
    std::vector<ProjectionType> projections;

    int dense_prefix = 100;
    double log_step_decades = 0.01;
    double t0 = 0.0;

    int threads = 0;
    bool skip_plots = false;
    bool run_python_plots = false;
    bool dedup_cases_by_omega = true;
    double omega_dedup_rel_tol = 1e-6;
};

static bool parse_bool_string(const std::string &s) {
    const std::string v = to_lower(trim(s));
    if (v == "1" || v == "true" || v == "yes" || v == "on") return true;
    if (v == "0" || v == "false" || v == "no" || v == "off") return false;
    throw std::runtime_error("Failed to parse bool: " + s);
}

static void load_config_file(const fs::path &path, RunnerConfig &cfg) {
    std::ifstream in(path);
    if (!in) {
        throw std::runtime_error("Failed to open config file: " + path.string());
    }

    std::string line;
    int lineno = 0;
    while (std::getline(in, line)) {
        ++lineno;
        line = trim(line);
        if (line.empty() || line[0] == '#') {
            continue;
        }

        auto [key, value] = parse_key_value(line);
        const std::string lkey = to_lower(key);

        if (lkey == "env") {
            cfg.env_id = value;
        } else if (lkey == "n_steps") {
            cfg.n_steps = parse_int(value);
        } else if (lkey == "n_runs") {
            cfg.n_runs = parse_int(value);
        } else if (lkey == "outdir") {
            cfg.outroot = value;
        } else if (lkey == "base_values" || lkey == "c_values") {
            cfg.base_values.clear();
            for (const auto &tok : split(value, ',')) {
                cfg.base_values.push_back(parse_double(tok));
            }
        } else if (lkey == "schedules") {
            cfg.schedules.clear();
            for (const auto &tok : split(value, ',')) {
                cfg.schedules.push_back(parse_schedule(tok));
            }
        } else if (lkey == "projections") {
            cfg.projections.clear();
            for (const auto &tok : split(value, ',')) {
                cfg.projections.push_back(parse_projection(tok));
            }
        } else if (lkey == "t0") {
            cfg.t0 = parse_double(value);
        } else if (lkey == "dense_prefix") {
            cfg.dense_prefix = parse_int(value);
        } else if (lkey == "log_step_decades") {
            cfg.log_step_decades = parse_double(value);
        } else if (lkey == "threads") {
            cfg.threads = parse_int(value);
        } else if (lkey == "skip_plots") {
            cfg.skip_plots = parse_bool_string(value);
        } else if (lkey == "plot_python") {
            cfg.run_python_plots = parse_bool_string(value);
        } else if (lkey == "dedup_cases_by_omega") {
            cfg.dedup_cases_by_omega = parse_bool_string(value);
        } else if (lkey == "omega_dedup_rel_tol") {
            cfg.omega_dedup_rel_tol = parse_double(value);
        } else if (starts_with(lkey, "set.")) {
            cfg.set_params[key.substr(4)] = value;
        } else if (starts_with(lkey, "sweep.")) {
            cfg.sweep_params[key.substr(6)] = split(value, ',');
        } else {
            throw std::runtime_error(
                "Unknown config key at " + path.string() + ":" + std::to_string(lineno) + ": " + key
            );
        }
    }
}

static void print_help(const char *argv0) {
    const auto envs = available_environment_ids();
    std::cout
        << "Usage:\n"
        << "  " << argv0 << " sweep [options]\n"
        << "  " << argv0 << " run   [options]\n\n"
        << "Options:\n"
        << "  --config <Path>         optional key=value config file (CLI overrides config)\n"
        << "  --env <Str>             environment id (default: toyexample)\n"
        << "  --n_steps <Int>         total steps per run (default: 10000000)\n"
        << "  --n_runs <Int>          number of runs (default: 48)\n"
        << "  --outdir <Path>         output root or explicit run dir (default: td_cxx_logs)\n"
        << "  --set <k=v>             fixed environment parameter (repeatable)\n"
        << "  --sweep <k=v1,v2,...>   swept environment parameter (repeatable)\n"
        << "  --base_values <csv>     c values in alpha_t = 1 / (c * g(t)) (default: 1e-3,1e-2,1e-1,1,10)\n"
        << "  --schedules <csv>       theory,theory_log2,inv_t,inv_sqrt_t,inv_t_2_3,inv_omega_t,constant_omega,constant\n"
        << "  --projections <csv>     none,oracle,upper\n"
        << "  --t0 <Float>            additive offset for 1/t-style schedules (default: 0)\n"
        << "  --dense_prefix <Int>    dense checkpoint prefix (default: 100)\n"
        << "  --log_step_decades <F>  log checkpoint stride in decades (default: 0.01)\n"
        << "  --threads <Int>         OpenMP thread count (default: system)\n"
        << "  --no_dedup_omega        keep all swept feature cases even if omega repeats\n"
        << "  --omega_dedup_rel_tol <F> relative tolerance for omega dedup (default: 1e-6)\n"
        << "  --plot_python           run v2 Python plotting/report scripts after sweep\n"
        << "  --skip_plots            skip plotting invocation\n"
        << "  -h, --help              show this help\n\n"
        << "Examples:\n"
        << "  " << argv0 << " sweep --env E3 --set eps1=1e-3 --set eps2=1e-2 --base_values 1e-3,1e-2,1e-1 --schedules inv_t,constant --projections none,oracle,upper\n"
        << "  " << argv0 << " sweep --env E7 --set m=64 --set alpha_max=1.57079632679 --sweep eps1=1e-2,1e-3 --base_values 1,10,100 --schedules theory\n"
        << "  " << argv0 << " sweep --config configs/study_e4.cfg\n"
        << "Available environments: ";
    for (size_t i = 0; i < envs.size(); ++i) {
        if (i > 0) {
            std::cout << ", ";
        }
        std::cout << envs[i];
    }
    std::cout << "\n";
}

static RunnerConfig parse_args(int argc, char **argv) {
    RunnerConfig cfg;
    cfg.base_values = {1e-3, 1e-2, 1e-1, 1.0, 10.0};
    cfg.schedules = {
        ScheduleType::Theory,
        ScheduleType::TheoryLog2,
        ScheduleType::InvT,
        ScheduleType::InvSqrtT,
        ScheduleType::InvTwoThirdsT,
        ScheduleType::InvOmegaT,
        ScheduleType::ConstantOmega,
        ScheduleType::Constant,
    };
    cfg.projections = {ProjectionType::None, ProjectionType::Oracle, ProjectionType::Upper};

    int i = 1;
    if (i < argc) {
        const std::string m = argv[i];
        if (m == "run" || m == "sweep") {
            cfg.mode = m;
            ++i;
        }
    }

    for (; i < argc; ++i) {
        const std::string arg = argv[i];
        auto need_val = [&](const std::string &name) -> std::string {
            if (i + 1 >= argc) {
                throw std::runtime_error("Missing value for " + name);
            }
            ++i;
            return argv[i];
        };

        if (arg == "-h" || arg == "--help") {
            print_help(argv[0]);
            std::exit(0);
        } else if (arg == "--config") {
            load_config_file(need_val(arg), cfg);
        } else if (arg == "--env") {
            cfg.env_id = need_val(arg);
        } else if (arg == "--n_steps") {
            cfg.n_steps = parse_int(need_val(arg));
        } else if (arg == "--n_runs") {
            cfg.n_runs = parse_int(need_val(arg));
        } else if (arg == "--outdir") {
            cfg.outroot = need_val(arg);
        } else if (arg == "--set") {
            auto [k, v] = parse_key_value(need_val(arg));
            cfg.set_params[k] = v;
        } else if (arg == "--sweep") {
            auto [k, v] = parse_key_value(need_val(arg));
            cfg.sweep_params[k] = split(v, ',');
        } else if (arg == "--base_values" || arg == "--c_values") {
            std::vector<std::string> toks = split(need_val(arg), ',');
            cfg.base_values.clear();
            cfg.base_values.reserve(toks.size());
            for (const auto &tok : toks) {
                cfg.base_values.push_back(parse_double(tok));
            }
        } else if (arg == "--schedules") {
            std::vector<std::string> toks = split(need_val(arg), ',');
            cfg.schedules.clear();
            for (const auto &tok : toks) {
                cfg.schedules.push_back(parse_schedule(tok));
            }
        } else if (arg == "--projections") {
            std::vector<std::string> toks = split(need_val(arg), ',');
            cfg.projections.clear();
            for (const auto &tok : toks) {
                cfg.projections.push_back(parse_projection(tok));
            }
        } else if (arg == "--t0") {
            cfg.t0 = parse_double(need_val(arg));
        } else if (arg == "--dense_prefix") {
            cfg.dense_prefix = parse_int(need_val(arg));
        } else if (arg == "--log_step_decades") {
            cfg.log_step_decades = parse_double(need_val(arg));
        } else if (arg == "--threads") {
            cfg.threads = parse_int(need_val(arg));
        } else if (arg == "--no_dedup_omega") {
            cfg.dedup_cases_by_omega = false;
        } else if (arg == "--omega_dedup_rel_tol") {
            cfg.omega_dedup_rel_tol = parse_double(need_val(arg));
        } else if (arg == "--skip_plots") {
            cfg.skip_plots = true;
        } else if (arg == "--plot_python") {
            cfg.run_python_plots = true;
        } else {
            throw std::runtime_error("Unknown argument: " + arg);
        }
    }

    if (cfg.mode == "run") {
        cfg.sweep_params.clear();
    }

    if (cfg.base_values.empty()) {
        throw std::runtime_error("base_values cannot be empty");
    }
    for (const double v : cfg.base_values) {
        if (!(v > 0.0) || !std::isfinite(v)) {
            throw std::runtime_error("c/base values must be positive finite numbers");
        }
    }

    if (cfg.schedules.empty()) {
        throw std::runtime_error("schedules cannot be empty");
    }
    if (cfg.projections.empty()) {
        throw std::runtime_error("projections cannot be empty");
    }
    if (!(cfg.omega_dedup_rel_tol >= 0.0) || !std::isfinite(cfg.omega_dedup_rel_tol)) {
        throw std::runtime_error("omega_dedup_rel_tol must be finite and >= 0");
    }

    return cfg;
}

static std::vector<ParamMap> parameter_product(const ParamMap &base, const SweepMap &sweeps) {
    std::vector<std::string> keys;
    keys.reserve(sweeps.size());
    for (const auto &kv : sweeps) {
        keys.push_back(kv.first);
    }
    std::sort(keys.begin(), keys.end());

    std::vector<ParamMap> cases;
    ParamMap current = base;

    std::function<void(size_t)> rec = [&](size_t idx) {
        if (idx >= keys.size()) {
            cases.push_back(current);
            return;
        }
        const auto &key = keys[idx];
        const auto it = sweeps.find(key);
        if (it == sweeps.end()) {
            rec(idx + 1);
            return;
        }
        for (const auto &v : it->second) {
            current[key] = v;
            rec(idx + 1);
        }
        current.erase(key);
    };

    if (keys.empty()) {
        cases.push_back(current);
    } else {
        rec(0);
    }
    return cases;
}

static std::vector<ParamMap> build_case_parameters(const std::string &env_id, const ParamMap &set_params, const SweepMap &sweep_params) {
    for (const auto &kv : set_params) {
        if (sweep_params.find(kv.first) != sweep_params.end()) {
            throw std::runtime_error("Parameter appears in both --set and --sweep: " + kv.first);
        }
    }

    SweepMap sweeps = sweep_params;
    if (sweeps.empty()) {
        SweepMap defaults = default_environment_sweeps(env_id);
        for (const auto &kv : defaults) {
            if (set_params.find(kv.first) == set_params.end()) {
                sweeps[kv.first] = kv.second;
            }
        }
    }
    return parameter_product(set_params, sweeps);
}

struct PreparedCase {
    ParamMap params;
    FiniteTDEnv env;
    ObjectiveMatrices metrics;
};

static bool omega_close(const double a, const double b, const double rel_tol) {
    if (!std::isfinite(a) || !std::isfinite(b)) {
        return false;
    }
    const double scale = std::max(1e-30, std::max(std::abs(a), std::abs(b)));
    return std::abs(a - b) <= rel_tol * scale;
}

static std::vector<PreparedCase> prepare_cases_with_optional_omega_dedup(
    const std::string &env_id,
    const std::vector<ParamMap> &case_params,
    const bool dedup_cases_by_omega,
    const double omega_rel_tol
) {
    std::vector<PreparedCase> prepared;
    prepared.reserve(case_params.size());

    int dropped = 0;
    for (const auto &params : case_params) {
        FiniteTDEnv env = build_environment(env_id, params);
        ObjectiveMatrices metrics = compute_objective_matrices(env);
        if (dedup_cases_by_omega) {
            bool is_dup = false;
            for (const auto &item : prepared) {
                if (omega_close(metrics.omega, item.metrics.omega, omega_rel_tol)) {
                    is_dup = true;
                    break;
                }
            }
            if (is_dup) {
                ++dropped;
                continue;
            }
        }
        prepared.push_back({params, std::move(env), std::move(metrics)});
    }

    if (dedup_cases_by_omega && dropped > 0) {
        std::cout << "Dedup by omega removed " << dropped
                  << " duplicated cases (tol=" << omega_rel_tol << ")\n";
    }
    return prepared;
}

static std::string case_label(const FiniteTDEnv &env) {
    std::ostringstream oss;
    oss << env.display_name;
    if (!env.metadata.empty()) {
        bool first = true;
        for (const auto &kv : env.metadata) {
            oss << (first ? " | " : " | ") << kv.first << "=" << kv.second;
            first = false;
        }
    }
    return oss.str();
}

static std::string case_slug(const FiniteTDEnv &env, const std::string &case_id) {
    std::vector<std::string> parts;
    parts.push_back(sanitize_token(env.env_id));
    parts.push_back("case-" + case_id);
    for (const auto &kv : env.metadata) {
        parts.push_back(sanitize_token(kv.first) + "-" + sanitize_token(kv.second));
    }
    std::ostringstream oss;
    for (size_t i = 0; i < parts.size(); ++i) {
        if (i > 0) oss << "__";
        oss << parts[i];
    }
    return oss.str();
}

static std::string fmt_float(const double x, const int precision = 16) {
    std::ostringstream oss;
    oss << std::setprecision(precision) << x;
    return oss.str();
}

static std::string detect_plot_python_executable() {
    const char *env_py = std::getenv("TDPLOT_PYTHON");
    if (env_py != nullptr) {
        const std::string v = trim(std::string(env_py));
        if (!v.empty()) {
            return v;
        }
    }

    const fs::path venv_py = fs::current_path() / ".venv_plot" / "bin" / "python";
    if (fs::exists(venv_py)) {
        return venv_py.string();
    }

    return "python3";
}

static void write_aggregated_csv(
    const fs::path &path,
    const AggregateResult &agg,
    const int n_steps,
    const ObjectiveMatrices &metrics,
    const FiniteTDEnv &env,
    const double theta_star_sq,
    const double tau_proxy
) {
    if (agg.timesteps.empty()) {
        throw std::runtime_error("No checkpoints in aggregate for " + path.string());
    }
    if (agg.timesteps.back() != n_steps) {
        throw std::runtime_error("Final checkpoint mismatch in " + path.string());
    }

    std::ofstream out(path);
    if (!out) {
        throw std::runtime_error("Failed to write " + path.string());
    }
    out << "timestep,E_D[||Vbar_t - V*||^2],E_A[||Vbar_t - V*||^2],E[||theta_t||^2],max_i<=T ||theta_i||^2,||theta^*||^2,std_D,std_A,std_max_theta,omega,kappa,lambda_sym,phi_max_sq,tau_proxy,gamma,alpha_mean,alpha_min,alpha_max\n";

    out << std::setprecision(12);
    for (size_t i = 0; i < agg.timesteps.size(); ++i) {
        out << agg.timesteps[i] << ','
            << agg.avg_vbar[i] << ','
            << agg.avg_vbar_A[i] << ','
            << agg.avg_theta_norms[i] << ','
            << agg.max_avg_theta << ','
            << theta_star_sq << ','
            << agg.std_vbar[i] << ','
            << agg.std_vbar_A[i] << ','
            << agg.max_std_theta << ','
            << metrics.omega << ','
            << metrics.kappa << ','
            << metrics.lambda_sym << ','
            << env.phi_max_sq << ','
            << tau_proxy << ','
            << env.gamma << ','
            << agg.alpha_mean[i] << ','
            << agg.alpha_min[i] << ','
            << agg.alpha_max[i]
            << '\n';
    }
}

static void write_run_csv(const fs::path &path, const std::vector<RunResult> &runs, const double theta_star_sq) {
    std::ofstream out(path);
    if (!out) {
        throw std::runtime_error("Failed to write " + path.string());
    }
    out << "run_idx,diverged,diverged_at,final_obj_D,final_obj_A,final_theta_norm,max_theta_norm,ratio_max_over_theta_star_sq,theta_star_norm_sq,max_alpha,max_proj_clip_count\n";
    out << std::setprecision(12);

    for (const auto &r : runs) {
        const double ratio = r.max_theta_norm / std::max(theta_star_sq, 1e-16);
        out << r.run_idx << ','
            << (r.diverged ? 1 : 0) << ','
            << r.diverged_at << ','
            << r.final_vbar << ','
            << r.final_vbar_A << ','
            << r.final_theta_norm << ','
            << r.max_theta_norm << ','
            << ratio << ','
            << theta_star_sq << ','
            << r.max_alpha << ','
            << r.proj_clip_count << '\n';
    }
}

static void maybe_run_python_plots(const fs::path &outdir) {
    const std::string run_dir = outdir.string();
    auto shell_quote = [](const std::string &s) {
        std::string out = "'";
        for (const char ch : s) {
            if (ch == '\'') {
                out += "'\\''";
            } else {
                out.push_back(ch);
            }
        }
        out.push_back('\'');
        return out;
    };

    const std::string pyexe = detect_plot_python_executable();
    const std::string pyexe_q = shell_quote(pyexe);
    const std::string run_dir_q = shell_quote(run_dir);
    const std::string report_out = (outdir / "report_v2_embedded.html").string();

    const std::string cmd1 = pyexe_q + " scripts/plot_suite_v2.py --run-dir " + run_dir_q;
    const std::string cmd2 = pyexe_q + " scripts/generate_embedded_report_v2.py --root " + run_dir_q +
                             " --out " + shell_quote(report_out);

    const int rc1 = std::system(cmd1.c_str());
    if (rc1 != 0) {
        std::cerr << "[warn] plot_suite_v2 failed with code " << rc1 << "\n";
    }
    const int rc2 = std::system(cmd2.c_str());
    if (rc2 != 0) {
        std::cerr << "[warn] generate_embedded_report_v2 failed with code " << rc2 << "\n";
    }
}

struct ManifestRow {
    std::string case_id;
    std::string env_id;
    std::string case_slug;
    std::string case_label;
    std::string algorithm;
    std::string schedule;
    std::string projection;
    std::string projection_radius;
    std::string param_name;
    std::string param_value;
    std::string agg_file;
    std::string run_file;
    std::string omega;
    std::string kappa;
    std::string lambda_sym;
    std::string phi_max_sq;
    std::string tau_proxy;
    std::string gamma;
    std::string theta_star_norm;
    std::string r_max;
    std::string metadata;
};

static std::string zero_pad(int x, int width) {
    std::ostringstream oss;
    oss << std::setw(width) << std::setfill('0') << x;
    return oss.str();
}

static std::string timestamp_now() {
    std::time_t now = std::time(nullptr);
    std::tm tmv{};
#ifdef _WIN32
    localtime_s(&tmv, &now);
#else
    localtime_r(&now, &tmv);
#endif
    char buf[32];
    std::strftime(buf, sizeof(buf), "%Y%m%d_%H%M%S", &tmv);
    return std::string(buf);
}

static int run(const RunnerConfig &cfg) {
    std::string env_id = canonical_env_id(cfg.env_id);

#ifdef _OPENMP
    if (cfg.threads > 0) {
        omp_set_num_threads(cfg.threads);
    }
    const int n_threads = omp_get_max_threads();
#else
    const int n_threads = 1;
#endif

    std::cout << "Using threads: " << n_threads << "\n";
    std::cout << "Environment: " << env_id << "\n";

    std::vector<int> checkpoints = checkpoint_indices(cfg.n_steps, cfg.dense_prefix, cfg.log_step_decades);

    fs::path base(cfg.outroot);
    fs::path outdir;
    if (starts_with(base.filename().string(), env_id + "_")) {
        outdir = base;
    } else {
        outdir = base / fs::path(env_id + "_" + timestamp_now());
    }
    fs::create_directories(outdir);

    const std::vector<ParamMap> case_params = build_case_parameters(env_id, cfg.set_params, cfg.sweep_params);
    if (case_params.empty()) {
        throw std::runtime_error("No environment cases to run");
    }
    std::vector<PreparedCase> prepared_cases = prepare_cases_with_optional_omega_dedup(
        env_id, case_params, cfg.dedup_cases_by_omega, cfg.omega_dedup_rel_tol
    );
    if (prepared_cases.empty()) {
        throw std::runtime_error("No environment cases after omega dedup");
    }

    std::vector<ManifestRow> manifest_rows;
    manifest_rows.reserve(prepared_cases.size() * cfg.base_values.size() * cfg.schedules.size() * cfg.projections.size());

    std::cout << "Cases: " << prepared_cases.size() << "\n";

    for (size_t case_index = 0; case_index < prepared_cases.size(); ++case_index) {
        const std::string cid = zero_pad(static_cast<int>(case_index + 1), 4);
        FiniteTDEnv &env = prepared_cases[case_index].env;
        ObjectiveMatrices &metrics = prepared_cases[case_index].metrics;
        const double theta_star_sq = metrics.theta_star_sq;

        std::cout << "Case " << cid << ": " << case_label(env) << "\n";
        std::cout << "  omega=" << metrics.omega << ", kappa=" << metrics.kappa
                  << ", phi_max_sq=" << env.phi_max_sq << ", tau_proxy=" << env.tau_proxy << "\n";

        const std::string slug = case_slug(env, cid);
        const std::string label = case_label(env);
        const std::string metadata_str = serialize_metadata(env.metadata);

        for (const auto sched : cfg.schedules) {
            for (const auto proj : cfg.projections) {
                const double proj_R = projection_radius(env, metrics, proj);
                for (const double param : cfg.base_values) {
                    AlgorithmSpec spec;
                    spec.schedule = sched;
                    spec.projection = proj;
                    spec.param = param;
                    spec.param_name = "c";

                    std::string sched_str = schedule_name(sched);
                    std::string proj_str = projection_name(proj);
                    std::cout << "  schedule=" << sched_str << ", projection=" << proj_str << ", c=" << param << " ..." << std::flush;

                    std::vector<RunResult> runs(static_cast<size_t>(cfg.n_runs));

#ifdef _OPENMP
#pragma omp parallel for schedule(static)
#endif
                    for (int run_idx = 0; run_idx < cfg.n_runs; ++run_idx) {
                        runs[static_cast<size_t>(run_idx)] = run_single_simulation(spec, run_idx + 1, cfg.n_steps, checkpoints, env, metrics, cfg.t0);
                    }

                    AggregateResult agg = aggregate_results(runs, checkpoints, spec, env, metrics, cfg.n_steps, cfg.t0);

                    std::ostringstream base_tag;
                    base_tag << std::scientific << std::setprecision(3) << param;
                    const std::string token = "case_" + cid + "__sched_" + sanitize_token(sched_str) + "__proj_" + sanitize_token(proj_str) + "__c_" + sanitize_token(base_tag.str());
                    const std::string agg_name = "agg_" + token + ".csv";
                    const std::string run_name = "runs_" + token + ".csv";

                    write_aggregated_csv(outdir / agg_name, agg, cfg.n_steps, metrics, env, theta_star_sq, env.tau_proxy);
                    write_run_csv(outdir / run_name, runs, theta_star_sq);

                    ManifestRow row;
                    row.case_id = cid;
                    row.env_id = env.env_id;
                    row.case_slug = slug;
                    row.case_label = label;
                    row.algorithm = "td0";
                    row.schedule = sched_str;
                    row.projection = proj_str;
                    row.projection_radius = fmt_float(proj_R);
                    row.param_name = "c";
                    row.param_value = fmt_float(param);
                    row.agg_file = agg_name;
                    row.run_file = run_name;
                    row.omega = fmt_float(metrics.omega);
                    row.kappa = fmt_float(metrics.kappa);
                    row.lambda_sym = fmt_float(metrics.lambda_sym);
                    row.phi_max_sq = fmt_float(env.phi_max_sq);
                    row.tau_proxy = fmt_float(env.tau_proxy);
                    row.gamma = fmt_float(env.gamma);
                    row.theta_star_norm = fmt_float(std::sqrt(std::max(0.0, theta_star_sq)));
                    row.r_max = fmt_float(env.r_max);
                    row.metadata = metadata_str;
                    manifest_rows.push_back(std::move(row));

                    std::cout << " done (div=" << agg.divergence_rate << ")\n";
                }
            }
        }
    }

    const fs::path manifest_path = outdir / "manifest.tsv";
    {
        std::ofstream mf(manifest_path);
        if (!mf) {
            throw std::runtime_error("Failed to write manifest: " + manifest_path.string());
        }
        mf << "case_id\tenv_id\tcase_slug\tcase_label\talgorithm\tschedule\tprojection\tprojection_radius\tparam_name\tparam_value\tagg_file\trun_file\tomega\tkappa\tlambda_sym\tphi_max_sq\ttau_proxy\tgamma\ttheta_star_norm\tr_max\tmetadata\n";
        for (const auto &r : manifest_rows) {
            mf << r.case_id << '\t'
               << r.env_id << '\t'
               << r.case_slug << '\t'
               << r.case_label << '\t'
               << r.algorithm << '\t'
               << r.schedule << '\t'
               << r.projection << '\t'
               << r.projection_radius << '\t'
               << r.param_name << '\t'
               << r.param_value << '\t'
               << r.agg_file << '\t'
               << r.run_file << '\t'
               << r.omega << '\t'
               << r.kappa << '\t'
               << r.lambda_sym << '\t'
               << r.phi_max_sq << '\t'
               << r.tau_proxy << '\t'
               << r.gamma << '\t'
               << r.theta_star_norm << '\t'
               << r.r_max << '\t'
               << r.metadata
               << '\n';
        }
    }

    std::cout << "Output directory: " << outdir << "\n";
    std::cout << "Manifest: " << manifest_path << "\n";

    if (!cfg.skip_plots && cfg.run_python_plots) {
        maybe_run_python_plots(outdir);
    }

    return 0;
}

} // namespace tdx

int main(int argc, char **argv) {
    try {
        const tdx::RunnerConfig cfg = tdx::parse_args(argc, argv);
        return tdx::run(cfg);
    } catch (const std::exception &e) {
        std::cerr << "[error] " << e.what() << "\n";
        return 1;
    }
}
