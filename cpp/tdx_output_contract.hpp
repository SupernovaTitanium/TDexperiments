#pragma once

namespace tdx::output_contract {

inline constexpr const char *kAggregateCsvHeader =
    "timestep,E_D[||Vbar_t - V*||^2],E_A[||Vbar_t - V*||^2],E[||theta_t||^2],max_i<=T ||theta_i||^2,||theta^*||^2,std_D,std_A,std_max_theta,omega,kappa,lambda_sym,phi_max_sq,tau_proxy,gamma,alpha_mean,alpha_min,alpha_max";

inline constexpr const char *kRunCsvHeader =
    "run_idx,diverged,diverged_at,final_obj_D,final_obj_A,final_theta_norm,max_theta_norm,ratio_max_over_theta_star_sq,theta_star_norm_sq,max_alpha,max_proj_clip_count";

inline constexpr const char *kManifestTsvHeader =
    "case_id\tenv_id\tcase_slug\tcase_label\talgorithm\tschedule\tprojection\tprojection_radius\tparam_name\tparam_value\tagg_file\trun_file\tomega\tkappa\tlambda_sym\tphi_max_sq\ttau_proxy\tgamma\ttheta_star_norm\tr_max\tmetadata";

} // namespace tdx::output_contract
