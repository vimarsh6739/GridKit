#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
gridkit_root="$(cd "${script_dir}/.." && pwd)"

baseline_summary="${GRIDKIT_SUNDIALS_BASELINE_SUMMARY:-${gridkit_root}/build/gridkit-sundials-local/gridkit_sundials_ida_baseline.json}"
reactant_summary="${GRIDKIT_REACTANT_EXPORT_SUMMARY:-${gridkit_root}/build/reactant-jacobian-export/reactant/genclassical_reactant_import_export.json}"
report="${GRIDKIT_REACTANT_JVP_EVALUATION:-${gridkit_root}/build/reactant-jacobian-export/reactant/gridkit_reactant_jvp_evaluation.json}"

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

json_string() {
  printf '"%s"' "$(json_escape "$1")"
}

json_string_or_null() {
  if [[ -n "$1" ]]; then
    json_string "$1"
  else
    printf 'null'
  fi
}

json_number_or_null() {
  if [[ "$1" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
    printf '%s' "$1"
  else
    printf 'null'
  fi
}

json_scalar_or_null() {
  if [[ -n "$1" && "$1" != "null" ]]; then
    printf '%s' "$1"
  else
    printf 'null'
  fi
}

json_bool() {
  if [[ "$1" == "true" ]]; then
    printf 'true'
  else
    printf 'false'
  fi
}

extract_json_scalar() {
  local file="$1"
  local key="$2"

  [[ -f "${file}" ]] || return 0
  sed -n -E "s/.*\"${key}\"[[:space:]]*:[[:space:]]*([^,}]+).*/\1/p" "${file}" |
    head -n 1 |
    tr -d '\r'
}

extract_json_scalar_last() {
  local file="$1"
  local key="$2"

  [[ -f "${file}" ]] || return 0
  sed -n -E "s/.*\"${key}\"[[:space:]]*:[[:space:]]*([^,}]+).*/\1/p" "${file}" |
    tail -n 1 |
    tr -d '\r'
}

extract_json_string() {
  local file="$1"
  local key="$2"

  [[ -f "${file}" ]] || return 0
  sed -n -E "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"([^\"]*)\".*/\1/p" "${file}" |
    head -n 1 |
    tr -d '\r'
}

extract_ctest_case_time() {
  local log="$1"

  [[ -f "${log}" ]] || return 0
  sed -n -E 's/.*Passed[[:space:]]+([0-9.]+)[[:space:]]+sec.*/\1/p' "${log}" |
    tail -n 1 |
    tr -d '\r'
}

extract_ctest_total_time() {
  local log="$1"

  [[ -f "${log}" ]] || return 0
  sed -n -E 's/.*Total Test time \(real\)[[:space:]]*=[[:space:]]*([0-9.]+)[[:space:]]+sec.*/\1/p' "${log}" |
    tail -n 1 |
    tr -d '\r'
}

extract_last_matching_line() {
  local log="$1"
  local pattern="$2"

  [[ -f "${log}" ]] || return 0
  grep -E "${pattern}" "${log}" | tail -n 1 || true
}

extract_line_metric() {
  local line="$1"
  local key="$2"

  printf '%s\n' "${line}" |
    sed -n -E "s/.*(^|[[:space:]])${key}=([^[:space:]]+).*/\2/p" |
    head -n 1
}

is_zero() {
  [[ "$1" == "0" ]]
}

all_zero() {
  local value
  for value in "$@"; do
    is_zero "${value}" || return 1
  done
}

line_reports_ok() {
  [[ "$1" == *": ok"* ]]
}

file_exists_bool() {
  if [[ -f "$1" ]]; then
    printf 'true'
  else
    printf 'false'
  fi
}

if [[ "${GRIDKIT_EVALUATION_RUN_BASELINE:-0}" == "1" ]]; then
  bash "${script_dir}/run_sundials_ida_baseline.sh"
fi

if [[ "${GRIDKIT_EVALUATION_RUN_REACTANT_EXPORT:-0}" == "1" ]]; then
  bash "${script_dir}/export_genclassical_reactant_import_mlir.sh"
fi

reactant_out_dir="$(dirname "${reactant_summary}")"

baseline_test_ida_log="$(extract_json_string "${baseline_summary}" "test_ida_log")"
baseline_three_bus_log="$(extract_json_string "${baseline_summary}" "three_bus_classical_log")"
if [[ -z "${baseline_test_ida_log}" || ! -f "${baseline_test_ida_log}" ]]; then
  baseline_test_ida_log="${gridkit_root}/build/gridkit-sundials-local/test_ida.log"
fi
if [[ -z "${baseline_three_bus_log}" || ! -f "${baseline_three_bus_log}" ]]; then
  baseline_three_bus_log="${gridkit_root}/build/gridkit-sundials-local/three_bus_classical.log"
fi

component_jvp_log="$(extract_json_string "${reactant_summary}" "runtime_real_smoke_log")"
component_sundials_log="$(extract_json_string "${reactant_summary}" "runtime_real_sundials_component_log")"
systemmodel_jvp_log="$(extract_json_string "${reactant_summary}" "smoke_log")"
systemmodel_sundials_log="$(extract_json_string "${reactant_summary}" "ida_sundials_smoke_log")"

if [[ -z "${component_jvp_log}" || ! -f "${component_jvp_log}" ]]; then
  component_jvp_log="${reactant_out_dir}/gridkit_semantic_bridge_runtime_glue_real_jvp_smoke.log"
fi
if [[ -z "${component_sundials_log}" || ! -f "${component_sundials_log}" ]]; then
  component_sundials_log="${reactant_out_dir}/gridkit_semantic_bridge_runtime_glue_real_sundials_component.log"
fi
if [[ -z "${systemmodel_jvp_log}" || ! -f "${systemmodel_jvp_log}" ]]; then
  systemmodel_jvp_log="${reactant_out_dir}/gridkit_systemmodel_layout_jvp_smoke.log"
fi
if [[ -z "${systemmodel_sundials_log}" || ! -f "${systemmodel_sundials_log}" ]]; then
  systemmodel_sundials_log="${reactant_out_dir}/gridkit_systemmodel_layout_ida_sundials_smoke.log"
fi

sundials_config_exit="$(extract_json_scalar "${baseline_summary}" "configure_exit_code")"
sundials_build_exit="$(extract_json_scalar "${baseline_summary}" "build_install_exit_code")"
gridkit_config_exit="$(extract_json_scalar_last "${baseline_summary}" "configure_exit_code")"
test_ida_build_exit="$(extract_json_scalar "${baseline_summary}" "test_ida_build_exit_code")"
test_ida_exit="$(extract_json_scalar "${baseline_summary}" "test_ida_exit_code")"
three_bus_build_exit="$(extract_json_scalar "${baseline_summary}" "three_bus_classical_build_exit_code")"
three_bus_exit="$(extract_json_scalar "${baseline_summary}" "three_bus_classical_exit_code")"
three_bus_metrics_exit="$(extract_json_scalar "${baseline_summary}" "three_bus_classical_metrics_exit_code")"

baseline_status="missing"
if [[ -f "${baseline_summary}" ]]; then
  baseline_status="failed"
  if all_zero "${sundials_config_exit}" "${sundials_build_exit}" "${gridkit_config_exit}" \
      "${test_ida_build_exit}" "${test_ida_exit}" "${three_bus_build_exit}" \
      "${three_bus_exit}"; then
    baseline_status="ok"
  fi
fi

test_ida_case_time="$(extract_ctest_case_time "${baseline_test_ida_log}")"
test_ida_total_time="$(extract_ctest_total_time "${baseline_test_ida_log}")"
three_bus_case_time="$(extract_ctest_case_time "${baseline_three_bus_log}")"
three_bus_total_time="$(extract_ctest_total_time "${baseline_three_bus_log}")"
baseline_three_bus_metrics_log="$(extract_json_string "${baseline_summary}" "three_bus_classical_metrics_log")"
if [[ -z "${baseline_three_bus_metrics_log}" || ! -f "${baseline_three_bus_metrics_log}" ]]; then
  baseline_three_bus_metrics_log="${gridkit_root}/build/gridkit-sundials-local/three_bus_classical_metrics.log"
fi

component_jvp_line="$(extract_last_matching_line "${component_jvp_log}" '^generated real JVP smoke:')"
component_sundials_line="$(extract_last_matching_line "${component_sundials_log}" '^generated real SUNDIALS component smoke:')"
systemmodel_jvp_line="$(extract_last_matching_line "${systemmodel_jvp_log}" '^systemmodel generated JVP smoke:')"
systemmodel_sundials_line="$(extract_last_matching_line "${systemmodel_sundials_log}" '^generated SystemModel SUNDIALS smoke:')"
baseline_three_bus_metrics_line="$(extract_json_string "${baseline_summary}" "line")"
if [[ "${baseline_three_bus_metrics_line}" != legacy\ KLU\ SUNDIALS\ stats:* ]]; then
  baseline_three_bus_metrics_line="$(
    extract_last_matching_line "${baseline_three_bus_metrics_log}" '^legacy KLU SUNDIALS stats:'
  )"
fi
baseline_solver_counters_available="false"
if [[ "${baseline_three_bus_metrics_line}" == legacy\ KLU\ SUNDIALS\ stats:* ]]; then
  baseline_solver_counters_available="true"
fi
baseline_jacobian_path="$(extract_json_string "${baseline_summary}" "jacobian_path")"
if [[ -z "${baseline_jacobian_path}" ]]; then
  baseline_jacobian_path="unknown"
fi
baseline_matches_requested_sparse_enzyme="false"
baseline_solver_label="SUNDIALS IDA with KLU"
case "${baseline_jacobian_path}" in
  enzyme_sparse)
    baseline_matches_requested_sparse_enzyme="true"
    baseline_solver_label="SUNDIALS IDA with Enzyme sparse Jacobian and KLU"
    ;;
  dense_fallback_no_enzyme)
    baseline_solver_label="SUNDIALS IDA with KLU and dense Jacobian fallback because GridKit was built without Enzyme"
    ;;
  dense_fallback_missing_component_jacobians)
    baseline_solver_label="SUNDIALS IDA with KLU and dense Jacobian fallback because some components lacked Enzyme Jacobians"
    ;;
esac

baseline_steps="$(extract_json_scalar "${baseline_summary}" "steps")"
baseline_residual_evals="$(extract_json_scalar "${baseline_summary}" "residual_evals")"
baseline_nonlinear_iters="$(extract_json_scalar "${baseline_summary}" "nonlinear_iters")"
baseline_nonlinear_convergence_fails="$(extract_json_scalar "${baseline_summary}" "nonlinear_convergence_fails")"
baseline_linear_decompositions="$(extract_json_scalar "${baseline_summary}" "linear_decompositions")"
baseline_error_test_fails="$(extract_json_scalar "${baseline_summary}" "error_test_fails")"
baseline_linear_iters="$(extract_json_scalar "${baseline_summary}" "linear_iters")"
baseline_linear_conv_fails="$(extract_json_scalar "${baseline_summary}" "linear_conv_fails")"
baseline_explicit_jacobian_evals="$(extract_json_scalar "${baseline_summary}" "explicit_jacobian_evals")"
baseline_jac_times_setup_evals="$(extract_json_scalar "${baseline_summary}" "jac_times_setup_evals")"
baseline_jac_times_evals="$(extract_json_scalar "${baseline_summary}" "jac_times_evals")"
baseline_linear_residual_evals="$(extract_json_scalar "${baseline_summary}" "linear_residual_evals")"
baseline_preconditioner_evals="$(extract_json_scalar "${baseline_summary}" "preconditioner_evals")"
baseline_preconditioner_solves="$(extract_json_scalar "${baseline_summary}" "preconditioner_solves")"
baseline_generated_jvp_configured="$(extract_json_scalar "${baseline_summary}" "generated_jvp_configured")"

if [[ -z "${baseline_steps}" || "${baseline_steps}" == "null" ]]; then
  baseline_steps="$(extract_line_metric "${baseline_three_bus_metrics_line}" "steps")"
fi
if [[ -z "${baseline_residual_evals}" || "${baseline_residual_evals}" == "null" ]]; then
  baseline_residual_evals="$(extract_line_metric "${baseline_three_bus_metrics_line}" "residual_evals")"
fi
if [[ -z "${baseline_nonlinear_iters}" || "${baseline_nonlinear_iters}" == "null" ]]; then
  baseline_nonlinear_iters="$(extract_line_metric "${baseline_three_bus_metrics_line}" "nonlinear_iters")"
fi
if [[ -z "${baseline_nonlinear_convergence_fails}" || "${baseline_nonlinear_convergence_fails}" == "null" ]]; then
  baseline_nonlinear_convergence_fails="$(extract_line_metric "${baseline_three_bus_metrics_line}" "nonlinear_convergence_fails")"
fi
if [[ -z "${baseline_linear_decompositions}" || "${baseline_linear_decompositions}" == "null" ]]; then
  baseline_linear_decompositions="$(extract_line_metric "${baseline_three_bus_metrics_line}" "linear_decompositions")"
fi
if [[ -z "${baseline_error_test_fails}" || "${baseline_error_test_fails}" == "null" ]]; then
  baseline_error_test_fails="$(extract_line_metric "${baseline_three_bus_metrics_line}" "error_test_fails")"
fi
if [[ -z "${baseline_linear_iters}" || "${baseline_linear_iters}" == "null" ]]; then
  baseline_linear_iters="$(extract_line_metric "${baseline_three_bus_metrics_line}" "linear_iters")"
fi
if [[ -z "${baseline_linear_conv_fails}" || "${baseline_linear_conv_fails}" == "null" ]]; then
  baseline_linear_conv_fails="$(extract_line_metric "${baseline_three_bus_metrics_line}" "linear_conv_fails")"
fi
if [[ -z "${baseline_explicit_jacobian_evals}" || "${baseline_explicit_jacobian_evals}" == "null" ]]; then
  baseline_explicit_jacobian_evals="$(extract_line_metric "${baseline_three_bus_metrics_line}" "explicit_jacobian_evals")"
fi
if [[ -z "${baseline_jac_times_setup_evals}" || "${baseline_jac_times_setup_evals}" == "null" ]]; then
  baseline_jac_times_setup_evals="$(extract_line_metric "${baseline_three_bus_metrics_line}" "jac_times_setup_evals")"
fi
if [[ -z "${baseline_jac_times_evals}" || "${baseline_jac_times_evals}" == "null" ]]; then
  baseline_jac_times_evals="$(extract_line_metric "${baseline_three_bus_metrics_line}" "jac_times_evals")"
fi
if [[ -z "${baseline_linear_residual_evals}" || "${baseline_linear_residual_evals}" == "null" ]]; then
  baseline_linear_residual_evals="$(extract_line_metric "${baseline_three_bus_metrics_line}" "linear_residual_evals")"
fi
if [[ -z "${baseline_preconditioner_evals}" || "${baseline_preconditioner_evals}" == "null" ]]; then
  baseline_preconditioner_evals="$(extract_line_metric "${baseline_three_bus_metrics_line}" "preconditioner_evals")"
fi
if [[ -z "${baseline_preconditioner_solves}" || "${baseline_preconditioner_solves}" == "null" ]]; then
  baseline_preconditioner_solves="$(extract_line_metric "${baseline_three_bus_metrics_line}" "preconditioner_solves")"
fi
if [[ -z "${baseline_generated_jvp_configured}" || "${baseline_generated_jvp_configured}" == "null" ]]; then
  baseline_generated_jvp_configured="$(extract_line_metric "${baseline_three_bus_metrics_line}" "generated_jvp_configured")"
fi

component_steps="$(extract_line_metric "${component_sundials_line}" "steps")"
component_residual_evals="$(extract_line_metric "${component_sundials_line}" "residual_evals")"
component_nonlinear_iters="$(extract_line_metric "${component_sundials_line}" "nonlinear_iters")"
component_linear_iters="$(extract_line_metric "${component_sundials_line}" "linear_iters")"
component_jac_times_evals="$(extract_line_metric "${component_sundials_line}" "jac_times_evals")"
component_explicit_jacobian_evals="$(extract_line_metric "${component_sundials_line}" "explicit_jacobian_evals")"

systemmodel_steps="$(extract_line_metric "${systemmodel_sundials_line}" "steps")"
systemmodel_residual_evals="$(extract_line_metric "${systemmodel_sundials_line}" "residual_evals")"
systemmodel_nonlinear_iters="$(extract_line_metric "${systemmodel_sundials_line}" "nonlinear_iters")"
systemmodel_linear_iters="$(extract_line_metric "${systemmodel_sundials_line}" "linear_iters")"
systemmodel_jac_times_evals="$(extract_line_metric "${systemmodel_sundials_line}" "jac_times_evals")"
systemmodel_explicit_jacobian_evals="$(extract_line_metric "${systemmodel_sundials_line}" "explicit_jacobian_evals")"

component_fd_status="$(extract_line_metric "${component_jvp_line}" "finite_difference")"
component_matrix_free_status="$(extract_line_metric "${component_jvp_line}" "matrix_free_oracle")"
component_explicit_csr_status="$(extract_line_metric "${component_jvp_line}" "explicit_csr_oracle")"
component_jvp_timing_iterations="$(extract_line_metric "${component_jvp_line}" "timing_iterations")"
component_generated_jvp_avg_us="$(extract_line_metric "${component_jvp_line}" "generated_jvp_avg_us")"
component_generated_jvp_total_us="$(extract_line_metric "${component_jvp_line}" "generated_jvp_total_us")"
component_matrix_free_avg_us="$(extract_line_metric "${component_jvp_line}" "matrix_free_oracle_avg_us")"
component_matrix_free_total_us="$(extract_line_metric "${component_jvp_line}" "matrix_free_oracle_total_us")"
component_explicit_csr_jvp_avg_us="$(extract_line_metric "${component_jvp_line}" "explicit_csr_jvp_avg_us")"
component_explicit_csr_jvp_total_us="$(extract_line_metric "${component_jvp_line}" "explicit_csr_jvp_total_us")"
systemmodel_fd_status="$(extract_line_metric "${systemmodel_jvp_line}" "finite_difference")"
systemmodel_explicit_sparse_status="$(extract_line_metric "${systemmodel_jvp_line}" "explicit_sparse_oracle")"
systemmodel_matrix_free_status="$(extract_line_metric "${systemmodel_jvp_line}" "matrix_free_oracle")"
systemmodel_jvp_timing_iterations="$(extract_line_metric "${systemmodel_jvp_line}" "timing_iterations")"
systemmodel_generated_jvp_avg_us="$(extract_line_metric "${systemmodel_jvp_line}" "generated_jvp_avg_us")"
systemmodel_generated_jvp_total_us="$(extract_line_metric "${systemmodel_jvp_line}" "generated_jvp_total_us")"
systemmodel_explicit_sparse_jvp_avg_us="$(extract_line_metric "${systemmodel_jvp_line}" "explicit_sparse_jvp_avg_us")"
systemmodel_explicit_sparse_jvp_total_us="$(extract_line_metric "${systemmodel_jvp_line}" "explicit_sparse_jvp_total_us")"
systemmodel_matrix_free_avg_us="$(extract_line_metric "${systemmodel_jvp_line}" "matrix_free_oracle_avg_us")"
systemmodel_matrix_free_total_us="$(extract_line_metric "${systemmodel_jvp_line}" "matrix_free_oracle_total_us")"

bridge_runtime_run_exit="$(extract_json_scalar "${reactant_summary}" "runtime_real_sundials_component_run_exit_code")"
systemmodel_sundials_run_exit="$(extract_json_scalar "${reactant_summary}" "ida_sundials_smoke_run_exit_code")"
matrix_free_selected_attr="$(extract_json_scalar "${reactant_summary}" "semantic_bridge_matrix_free_selected_attr")"
allow_matrix_free_attrs="$(extract_json_scalar "${reactant_summary}" "semantic_bridge_allow_matrix_free_attrs")"
unique_host_jacobian_bridge_attr="$(extract_json_scalar "${reactant_summary}" "semantic_bridge_unique_host_jacobian_bridge_attr")"
unique_host_jacobian_bridge_solves="$(extract_json_scalar "${reactant_summary}" "semantic_bridge_unique_host_jacobian_bridge_solves")"
semantic_bridge_jacobian_action_solves="$(extract_json_scalar "${reactant_summary}" "semantic_bridge_jacobian_action_solves")"
ida_set_jac_times_calls="$(extract_json_scalar "${reactant_summary}" "semantic_bridge_ida_set_jac_times_calls")"
iterative_solver_calls="$(extract_json_scalar "${reactant_summary}" "semantic_bridge_iterative_solver_calls")"
systemmodel_success_lines="$(extract_json_scalar "${reactant_summary}" "systemmodel_generated_jvp_sundials_success_lines")"
systemmodel_explicit_sparse_success_lines="$(extract_json_scalar "${reactant_summary}" "systemmodel_generated_jvp_explicit_sparse_success_lines")"
systemmodel_matrix_free_success_lines="$(extract_json_scalar "${reactant_summary}" "systemmodel_generated_jvp_matrix_free_success_lines")"
semantic_materializations="$(extract_json_scalar "${reactant_summary}" "semantic_jacobian_materializations")"
semantic_actions="$(extract_json_scalar "${reactant_summary}" "semantic_jacobian_actions")"
ida_host_explicit_solves="$(extract_json_scalar "${reactant_summary}" "ida_host_semantic_sundials_ida_explicit_matrix_solves")"

compiler_status="missing"
if [[ -f "${reactant_summary}" ]]; then
  compiler_status="failed"
  if line_reports_ok "${component_sundials_line}" && line_reports_ok "${systemmodel_sundials_line}" &&
      is_zero "${bridge_runtime_run_exit}" && is_zero "${systemmodel_sundials_run_exit}"; then
    compiler_status="ok"
  fi
fi

oracle_status="missing"
if [[ -n "${component_jvp_line}" || -n "${systemmodel_jvp_line}" ]]; then
  oracle_status="failed"
  if [[ "${component_fd_status}" == "ok" &&
        "${component_matrix_free_status}" == "ok" &&
        "${component_explicit_csr_status}" == "ok" &&
        "${systemmodel_fd_status}" == "ok" &&
        "${systemmodel_explicit_sparse_status}" == "ok" &&
        "${systemmodel_matrix_free_status}" == "ok" ]]; then
    oracle_status="ok"
  fi
fi

mkdir -p "$(dirname "${report}")"

{
  printf '{\n'
  printf '  "generated_at_utc": %s,\n' "$(json_string "$(date -u '+%Y-%m-%dT%H:%M:%SZ')")"
  printf '  "reproduce": {\n'
  printf '    "baseline": %s,\n' "$(json_string "bash GridKit/scripts/run_sundials_ida_baseline.sh")"
  printf '    "reactant_export": %s,\n' "$(json_string "bash GridKit/scripts/export_genclassical_reactant_import_mlir.sh")"
  printf '    "evaluation": %s,\n' "$(json_string "bash GridKit/scripts/evaluate_reactant_jvp_pipeline.sh")"
  printf '    "rerun_all": %s\n' "$(json_string "GRIDKIT_EVALUATION_RUN_BASELINE=1 GRIDKIT_EVALUATION_RUN_REACTANT_EXPORT=1 bash GridKit/scripts/evaluate_reactant_jvp_pipeline.sh")"
  printf '  },\n'
  printf '  "artifacts": {\n'
  printf '    "baseline_summary": %s,\n' "$(json_string "${baseline_summary}")"
  printf '    "baseline_summary_exists": %s,\n' "$(file_exists_bool "${baseline_summary}")"
  printf '    "reactant_summary": %s,\n' "$(json_string "${reactant_summary}")"
  printf '    "reactant_summary_exists": %s,\n' "$(file_exists_bool "${reactant_summary}")"
  printf '    "component_jvp_log": %s,\n' "$(json_string "${component_jvp_log}")"
  printf '    "component_sundials_log": %s,\n' "$(json_string "${component_sundials_log}")"
  printf '    "systemmodel_jvp_log": %s,\n' "$(json_string "${systemmodel_jvp_log}")"
  printf '    "systemmodel_sundials_log": %s\n' "$(json_string "${systemmodel_sundials_log}")"
  printf '  },\n'
  printf '  "qualification": {\n'
  printf '    "direct_speedup_claim": false,\n'
  printf '    "solver_change": %s,\n' "$(json_string "A uses ${baseline_solver_label}; C uses compiler-generated JacTimes plus SPGMR iterative solves.")"
  printf '    "interpretation": %s\n' "$(json_string "This report proves semantic behavior, generated callback registration, available solver counters, and numerical agreement. It does not present the direct-versus-iterative solver difference as a pure compiler speedup.")"
  printf '  },\n'
  printf '  "A_explicit_sparse_jacobian_klu": {\n'
  printf '    "status": %s,\n' "$(json_string "${baseline_status}")"
  printf '    "solver": %s,\n' "$(json_string "${baseline_solver_label}")"
  printf '    "jacobian_path": %s,\n' "$(json_string "${baseline_jacobian_path}")"
  printf '    "matches_requested_sparse_enzyme_baseline": %s,\n' "$(json_bool "${baseline_matches_requested_sparse_enzyme}")"
  printf '    "summary_exit_codes": {\n'
  printf '      "sundials_configure": %s,\n' "$(json_scalar_or_null "${sundials_config_exit}")"
  printf '      "sundials_build_install": %s,\n' "$(json_scalar_or_null "${sundials_build_exit}")"
  printf '      "gridkit_configure": %s,\n' "$(json_scalar_or_null "${gridkit_config_exit}")"
  printf '      "test_ida_build": %s,\n' "$(json_scalar_or_null "${test_ida_build_exit}")"
  printf '      "test_ida": %s,\n' "$(json_scalar_or_null "${test_ida_exit}")"
  printf '      "three_bus_classical_build": %s,\n' "$(json_scalar_or_null "${three_bus_build_exit}")"
  printf '      "three_bus_classical": %s,\n' "$(json_scalar_or_null "${three_bus_exit}")"
  printf '      "three_bus_classical_metrics": %s\n' "$(json_scalar_or_null "${three_bus_metrics_exit}")"
  printf '    },\n'
  printf '    "ctest": {\n'
  printf '      "IDATest": {\n'
  printf '        "case_time_sec": %s,\n' "$(json_number_or_null "${test_ida_case_time}")"
  printf '        "total_test_time_sec": %s,\n' "$(json_number_or_null "${test_ida_total_time}")"
  printf '        "log": %s\n' "$(json_string "${baseline_test_ida_log}")"
  printf '      },\n'
  printf '      "ThreeBusClassical": {\n'
  printf '        "case_time_sec": %s,\n' "$(json_number_or_null "${three_bus_case_time}")"
  printf '        "total_test_time_sec": %s,\n' "$(json_number_or_null "${three_bus_total_time}")"
  printf '        "log": %s\n' "$(json_string "${baseline_three_bus_log}")"
  printf '      }\n'
  printf '    },\n'
  printf '    "solver_counters_available": %s,\n' "$(json_bool "${baseline_solver_counters_available}")"
  printf '    "solver_counters": {\n'
  printf '      "line": %s,\n' "$(json_string_or_null "${baseline_three_bus_metrics_line}")"
  printf '      "log": %s,\n' "$(json_string "${baseline_three_bus_metrics_log}")"
  printf '      "steps": %s,\n' "$(json_number_or_null "${baseline_steps}")"
  printf '      "residual_evals": %s,\n' "$(json_number_or_null "${baseline_residual_evals}")"
  printf '      "nonlinear_iters": %s,\n' "$(json_number_or_null "${baseline_nonlinear_iters}")"
  printf '      "nonlinear_convergence_fails": %s,\n' "$(json_number_or_null "${baseline_nonlinear_convergence_fails}")"
  printf '      "linear_decompositions": %s,\n' "$(json_number_or_null "${baseline_linear_decompositions}")"
  printf '      "error_test_fails": %s,\n' "$(json_number_or_null "${baseline_error_test_fails}")"
  printf '      "linear_iters": %s,\n' "$(json_number_or_null "${baseline_linear_iters}")"
  printf '      "linear_conv_fails": %s,\n' "$(json_number_or_null "${baseline_linear_conv_fails}")"
  printf '      "explicit_jacobian_evals": %s,\n' "$(json_number_or_null "${baseline_explicit_jacobian_evals}")"
  printf '      "jac_times_setup_evals": %s,\n' "$(json_number_or_null "${baseline_jac_times_setup_evals}")"
  printf '      "jac_times_evals": %s,\n' "$(json_number_or_null "${baseline_jac_times_evals}")"
  printf '      "linear_residual_evals": %s,\n' "$(json_number_or_null "${baseline_linear_residual_evals}")"
  printf '      "preconditioner_evals": %s,\n' "$(json_number_or_null "${baseline_preconditioner_evals}")"
  printf '      "preconditioner_solves": %s,\n' "$(json_number_or_null "${baseline_preconditioner_solves}")"
  printf '      "generated_jvp_configured": %s\n' "$(json_number_or_null "${baseline_generated_jvp_configured}")"
  printf '    },\n'
  printf '    "missing_counters": [\n'
  printf '      "derivative_time",\n'
  printf '      "sparse_assembly_time",\n'
  printf '      "memory"\n'
  printf '    ]\n'
  printf '  },\n'
  printf '  "B_raised_before_jvp_optimization": {\n'
  printf '    "status": %s,\n' "$(json_string "not_executable_as_a_solver_path")"
  printf '    "reason": %s,\n' "$(json_string "The raised artifact preserves explicit Jacobian materialization semantics, but the executable pre-optimization GridKit solve still belongs to the legacy host/KLU path; this artifact is IR evidence rather than a separately runnable IDA variant.")"
  printf '    "semantic_jacobian_materializations": %s,\n' "$(json_scalar_or_null "${semantic_materializations}")"
  printf '    "semantic_jacobian_actions": %s,\n' "$(json_scalar_or_null "${semantic_actions}")"
  printf '    "ida_host_explicit_matrix_solves_recovered": %s\n' "$(json_scalar_or_null "${ida_host_explicit_solves}")"
  printf '  },\n'
  printf '  "C_compiler_transformed_jvp_iterative_ida": {\n'
  printf '    "status": %s,\n' "$(json_string "${compiler_status}")"
  printf '    "solver": %s,\n' "$(json_string "SUNDIALS IDA with compiler-generated JacTimes callback and SPGMR")"
  printf '    "selection_evidence": {\n'
  printf '      "matrix_free_selected_attr": %s,\n' "$(json_scalar_or_null "${matrix_free_selected_attr}")"
  printf '      "allow_matrix_free_attrs": %s,\n' "$(json_scalar_or_null "${allow_matrix_free_attrs}")"
  printf '      "unique_host_jacobian_bridge_attr": %s,\n' "$(json_scalar_or_null "${unique_host_jacobian_bridge_attr}")"
  printf '      "unique_host_jacobian_bridge_solves": %s,\n' "$(json_scalar_or_null "${unique_host_jacobian_bridge_solves}")"
  printf '      "jacobian_action_solves": %s,\n' "$(json_scalar_or_null "${semantic_bridge_jacobian_action_solves}")"
  printf '      "ida_set_jac_times_calls": %s,\n' "$(json_scalar_or_null "${ida_set_jac_times_calls}")"
  printf '      "iterative_solver_calls": %s,\n' "$(json_scalar_or_null "${iterative_solver_calls}")"
  printf '      "component_sundials_run_exit_code": %s,\n' "$(json_scalar_or_null "${bridge_runtime_run_exit}")"
  printf '      "systemmodel_sundials_run_exit_code": %s\n' "$(json_scalar_or_null "${systemmodel_sundials_run_exit}")"
  printf '    },\n'
  printf '    "standalone_jvp_timing": {\n'
  printf '      "component": {\n'
  printf '        "iterations": %s,\n' "$(json_number_or_null "${component_jvp_timing_iterations}")"
  printf '        "generated_jvp_avg_us": %s,\n' "$(json_number_or_null "${component_generated_jvp_avg_us}")"
  printf '        "generated_jvp_total_us": %s,\n' "$(json_number_or_null "${component_generated_jvp_total_us}")"
  printf '        "explicit_csr_jvp_avg_us": %s,\n' "$(json_number_or_null "${component_explicit_csr_jvp_avg_us}")"
  printf '        "explicit_csr_jvp_total_us": %s,\n' "$(json_number_or_null "${component_explicit_csr_jvp_total_us}")"
  printf '        "matrix_free_oracle_avg_us": %s,\n' "$(json_number_or_null "${component_matrix_free_avg_us}")"
  printf '        "matrix_free_oracle_total_us": %s\n' "$(json_number_or_null "${component_matrix_free_total_us}")"
  printf '      },\n'
  printf '      "systemmodel": {\n'
  printf '        "iterations": %s,\n' "$(json_number_or_null "${systemmodel_jvp_timing_iterations}")"
  printf '        "generated_jvp_avg_us": %s,\n' "$(json_number_or_null "${systemmodel_generated_jvp_avg_us}")"
  printf '        "generated_jvp_total_us": %s,\n' "$(json_number_or_null "${systemmodel_generated_jvp_total_us}")"
  printf '        "explicit_sparse_jvp_avg_us": %s,\n' "$(json_number_or_null "${systemmodel_explicit_sparse_jvp_avg_us}")"
  printf '        "explicit_sparse_jvp_total_us": %s,\n' "$(json_number_or_null "${systemmodel_explicit_sparse_jvp_total_us}")"
  printf '        "matrix_free_oracle_avg_us": %s,\n' "$(json_number_or_null "${systemmodel_matrix_free_avg_us}")"
  printf '        "matrix_free_oracle_total_us": %s\n' "$(json_number_or_null "${systemmodel_matrix_free_total_us}")"
  printf '      }\n'
  printf '    },\n'
  printf '    "component_smoke": {\n'
  printf '      "line": %s,\n' "$(json_string_or_null "${component_sundials_line}")"
  printf '      "steps": %s,\n' "$(json_number_or_null "${component_steps}")"
  printf '      "residual_evals": %s,\n' "$(json_number_or_null "${component_residual_evals}")"
  printf '      "nonlinear_iters": %s,\n' "$(json_number_or_null "${component_nonlinear_iters}")"
  printf '      "linear_iters": %s,\n' "$(json_number_or_null "${component_linear_iters}")"
  printf '      "jac_times_evals": %s,\n' "$(json_number_or_null "${component_jac_times_evals}")"
  printf '      "explicit_jacobian_evals": %s\n' "$(json_number_or_null "${component_explicit_jacobian_evals}")"
  printf '    },\n'
  printf '    "systemmodel_smoke": {\n'
  printf '      "line": %s,\n' "$(json_string_or_null "${systemmodel_sundials_line}")"
  printf '      "steps": %s,\n' "$(json_number_or_null "${systemmodel_steps}")"
  printf '      "residual_evals": %s,\n' "$(json_number_or_null "${systemmodel_residual_evals}")"
  printf '      "nonlinear_iters": %s,\n' "$(json_number_or_null "${systemmodel_nonlinear_iters}")"
  printf '      "linear_iters": %s,\n' "$(json_number_or_null "${systemmodel_linear_iters}")"
  printf '      "jac_times_evals": %s,\n' "$(json_number_or_null "${systemmodel_jac_times_evals}")"
  printf '      "explicit_jacobian_evals": %s\n' "$(json_number_or_null "${systemmodel_explicit_jacobian_evals}")"
  printf '    }\n'
  printf '  },\n'
  printf '  "D_matrix_free_jvp_oracle": {\n'
  printf '    "status": %s,\n' "$(json_string "${oracle_status}")"
  printf '    "role": %s,\n' "$(json_string "Correctness oracle and engineering baseline only; not the primary implementation path.")"
  printf '    "component": {\n'
  printf '      "line": %s,\n' "$(json_string_or_null "${component_jvp_line}")"
  printf '      "finite_difference": %s,\n' "$(json_string_or_null "${component_fd_status}")"
  printf '      "matrix_free_oracle": %s,\n' "$(json_string_or_null "${component_matrix_free_status}")"
  printf '      "explicit_csr_oracle": %s,\n' "$(json_string_or_null "${component_explicit_csr_status}")"
  printf '      "matrix_free_oracle_avg_us": %s,\n' "$(json_number_or_null "${component_matrix_free_avg_us}")"
  printf '      "explicit_csr_jvp_avg_us": %s\n' "$(json_number_or_null "${component_explicit_csr_jvp_avg_us}")"
  printf '    },\n'
  printf '    "systemmodel": {\n'
  printf '      "line": %s,\n' "$(json_string_or_null "${systemmodel_jvp_line}")"
  printf '      "finite_difference": %s,\n' "$(json_string_or_null "${systemmodel_fd_status}")"
  printf '      "explicit_sparse_oracle": %s,\n' "$(json_string_or_null "${systemmodel_explicit_sparse_status}")"
  printf '      "matrix_free_oracle": %s,\n' "$(json_string_or_null "${systemmodel_matrix_free_status}")"
  printf '      "matrix_free_oracle_avg_us": %s,\n' "$(json_number_or_null "${systemmodel_matrix_free_avg_us}")"
  printf '      "explicit_sparse_jvp_avg_us": %s,\n' "$(json_number_or_null "${systemmodel_explicit_sparse_jvp_avg_us}")"
  printf '      "sundials_success_lines": %s,\n' "$(json_scalar_or_null "${systemmodel_success_lines}")"
  printf '      "explicit_sparse_success_lines": %s,\n' "$(json_scalar_or_null "${systemmodel_explicit_sparse_success_lines}")"
  printf '      "matrix_free_success_lines": %s\n' "$(json_scalar_or_null "${systemmodel_matrix_free_success_lines}")"
  printf '    }\n'
  printf '  },\n'
  printf '  "phase8_metric_coverage": {\n'
  printf '    "total_runtime": %s,\n' "$(json_string "Available as coarse ctest times for the legacy KLU baseline; generated smokes are counter and microbenchmark checks, not end-to-end timed benchmarks.")"
  printf '    "derivative_computation_time": %s,\n' "$(json_string "Partially available as standalone smoke microbenchmarks for generated JVP and explicit sparse J*v paths; not yet available inside the legacy KLU solver run.")"
  printf '    "sparse_assembly_time": %s,\n' "$(json_string "Partially available as explicit sparse J*v smoke timing, which includes sparse Jacobian materialization plus multiplication for the tiny smoke models.")"
  printf '    "jvp_time": %s,\n' "$(json_string "Available as standalone smoke microbenchmarks for the generated JacTimes/JVP path; solver-integrated callback wall time still needs instrumentation.")"
  printf '    "memory": %s,\n' "$(json_string "Unavailable; no peak-memory instrumentation is wired into the baseline or generated smokes yet.")"
  printf '    "nonlinear_iterations": %s,\n' "$(json_string "Available for the legacy KLU ThreeBusClassical baseline and generated component/SystemModel smokes.")"
  printf '    "linear_iterations": %s,\n' "$(json_string "Available for the legacy KLU ThreeBusClassical baseline and generated component/SystemModel smokes.")"
  printf '    "residual_evaluations": %s,\n' "$(json_string "Available for the legacy KLU ThreeBusClassical baseline and generated component/SystemModel smokes.")"
  printf '    "derivative_or_jvp_evaluations": %s,\n' "$(json_string "KLU explicit Jacobian evaluations are available for the legacy baseline; JacTimes evaluations are available for generated smokes and explicit Jacobian evaluations are reported as zero there.")"
  printf '    "convergence_behavior": %s,\n' "$(json_string "Available as successful completion plus step/iteration counters for generated smokes and pass/fail ctest status for baseline.")"
  printf '    "final_numerical_agreement": %s\n' "$(json_string "Available from finite-difference, explicit CSR/sparse, and MatrixFree oracle checks in generated JVP smokes.")"
  printf '  },\n'
  printf '  "materialization_savings_vs_solver_costs": {\n'
  printf '    "avoids_solver_time_explicit_jacobian_materialization": %s,\n' "$(json_bool "$([[ "${component_explicit_jacobian_evals}" == "0" && "${systemmodel_explicit_jacobian_evals}" == "0" ]] && printf true || printf false)")"
  printf '    "baseline_explicit_jacobian_evals": %s,\n' "$(json_number_or_null "${baseline_explicit_jacobian_evals}")"
  printf '    "baseline_jac_times_evals": %s,\n' "$(json_number_or_null "${baseline_jac_times_evals}")"
  printf '    "component_jac_times_evals": %s,\n' "$(json_number_or_null "${component_jac_times_evals}")"
  printf '    "systemmodel_jac_times_evals": %s,\n' "$(json_number_or_null "${systemmodel_jac_times_evals}")"
  printf '    "component_generated_jvp_avg_us": %s,\n' "$(json_number_or_null "${component_generated_jvp_avg_us}")"
  printf '    "component_explicit_csr_jvp_avg_us": %s,\n' "$(json_number_or_null "${component_explicit_csr_jvp_avg_us}")"
  printf '    "systemmodel_generated_jvp_avg_us": %s,\n' "$(json_number_or_null "${systemmodel_generated_jvp_avg_us}")"
  printf '    "systemmodel_explicit_sparse_jvp_avg_us": %s,\n' "$(json_number_or_null "${systemmodel_explicit_sparse_jvp_avg_us}")"
  printf '    "direct_vs_iterative_solver_costs_separated": true,\n'
  printf '    "note": %s\n' "$(json_string "The report separates materialization avoidance evidence from costs introduced by changing KLU direct solves to SPGMR iterative solves.")"
  printf '  }\n'
  printf '}\n'
} > "${report}"

echo "wrote ${report}"
echo "A legacy KLU baseline: ${baseline_status} (${baseline_jacobian_path})"
echo "C compiler-generated JVP + iterative IDA: ${compiler_status}"
echo "D MatrixFree oracle: ${oracle_status}"
