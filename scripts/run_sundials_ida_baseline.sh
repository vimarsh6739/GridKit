#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
gridkit_root="$(cd "${script_dir}/.." && pwd)"

sundials_repo="${SUNDIALS_REPO:-https://github.com/LLNL/sundials.git}"
sundials_tag="${SUNDIALS_TAG:-v7.4.0}"
sundials_src="${SUNDIALS_SRC:-${gridkit_root}/build/deps/sundials-src}"
sundials_build="${SUNDIALS_BUILD:-${gridkit_root}/build/deps/sundials-build}"
sundials_install="${SUNDIALS_INSTALL:-${gridkit_root}/build/deps/sundials-install}"
gridkit_build="${GRIDKIT_SUNDIALS_BUILD:-${gridkit_root}/build/gridkit-sundials-local}"
summary="${GRIDKIT_SUNDIALS_BASELINE_SUMMARY:-${gridkit_build}/gridkit_sundials_ida_baseline.json}"
klu_include_dir="${KLU_INCLUDE_DIR:-/usr/include/suitesparse}"
klu_library_dir="${KLU_LIBRARY_DIR:-/usr/lib/x86_64-linux-gnu}"
gridkit_enable_enzyme="${GRIDKIT_SUNDIALS_BASELINE_ENABLE_ENZYME:-OFF}"
enzyme_dir="${ENZYME_DIR:-${gridkit_root}/build/deps/enzyme-llvm23-build}"

case "${gridkit_enable_enzyme}" in
  1 | ON | on | TRUE | true | YES | yes)
    gridkit_enable_enzyme="ON"
    ;;
  *)
    gridkit_enable_enzyme="OFF"
    ;;
esac

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

json_string() {
  printf '"%s"' "$(json_escape "$1")"
}

json_number_or_null() {
  if [[ "$1" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
    printf '%s' "$1"
  else
    printf 'null'
  fi
}

run_step() {
  local name="$1"
  local log="$2"
  shift 2

  mkdir -p "$(dirname "${log}")"
  set +e
  "$@" > "${log}" 2>&1
  local status=$?
  set -e
  printf -v "${name}" '%s' "${status}"
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

if [[ ! -d "${sundials_src}/.git" ]]; then
  mkdir -p "$(dirname "${sundials_src}")"
  git clone --depth 1 --branch "${sundials_tag}" "${sundials_repo}" "${sundials_src}"
else
  git -C "${sundials_src}" fetch --depth 1 origin "refs/tags/${sundials_tag}:refs/tags/${sundials_tag}" || true
  git -C "${sundials_src}" checkout "${sundials_tag}"
fi

mkdir -p "${gridkit_build}"
sundials_config_log="${sundials_build}/configure.log"
sundials_build_log="${sundials_build}/build_install.log"
gridkit_config_log="${gridkit_build}/configure.log"
test_ida_build_log="${gridkit_build}/test_ida_build.log"
test_ida_log="${gridkit_build}/test_ida.log"
three_bus_build_log="${gridkit_build}/three_bus_classical_build.log"
three_bus_log="${gridkit_build}/three_bus_classical.log"
three_bus_metrics_log="${gridkit_build}/three_bus_classical_metrics.log"
three_bus_exe="${gridkit_build}/examples/PhasorDynamics/Tiny/ThreeBus/Classical/ThreeBusClassical"

run_step sundials_config_status "${sundials_config_log}" \
  cmake -S "${sundials_src}" -B "${sundials_build}" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="${sundials_install}" \
    -DBUILD_SHARED_LIBS=ON \
    -DENABLE_MPI=OFF \
    -DENABLE_KLU=ON \
    -DKLU_INCLUDE_DIR="${klu_include_dir}" \
    -DKLU_LIBRARY_DIR="${klu_library_dir}" \
    -DEXAMPLES_ENABLE_C=OFF \
    -DEXAMPLES_ENABLE_CXX=OFF \
    -DEXAMPLES_INSTALL=OFF

if [[ "${sundials_config_status}" -eq 0 ]]; then
  run_step sundials_build_status "${sundials_build_log}" \
    cmake --build "${sundials_build}" --target install -j"$(nproc)"
else
  sundials_build_status=""
fi

if [[ "${sundials_config_status}" -eq 0 && "${sundials_build_status}" -eq 0 ]]; then
  run_step gridkit_config_status "${gridkit_config_log}" \
    cmake -S "${gridkit_root}" -B "${gridkit_build}" -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DGridKit_ENABLE_SUNDIALS=ON \
      -DSUNDIALS_DIR="${sundials_install}" \
      -DGridKit_ENABLE_ENZYME="${gridkit_enable_enzyme}" \
      -DENZYME_DIR="${enzyme_dir}" \
      -DGridKit_ENABLE_IPOPT=OFF
else
  gridkit_config_status=""
fi

if [[ -n "${gridkit_config_status}" && "${gridkit_config_status}" -eq 0 ]]; then
  run_step test_ida_build_status "${test_ida_build_log}" \
    cmake --build "${gridkit_build}" --target test_ida -j"$(nproc)"
else
  test_ida_build_status=""
fi

if [[ -n "${test_ida_build_status}" && "${test_ida_build_status}" -eq 0 ]]; then
  run_step test_ida_status "${test_ida_log}" \
    ctest --test-dir "${gridkit_build}" -R '^IDATest$' --output-on-failure
else
  test_ida_status=""
fi

if [[ -n "${gridkit_config_status}" && "${gridkit_config_status}" -eq 0 ]]; then
  run_step three_bus_build_status "${three_bus_build_log}" \
    cmake --build "${gridkit_build}" --target ThreeBusClassical -j"$(nproc)"
else
  three_bus_build_status=""
fi

if [[ -n "${three_bus_build_status}" && "${three_bus_build_status}" -eq 0 ]]; then
  run_step three_bus_status "${three_bus_log}" \
    ctest --test-dir "${gridkit_build}" -R '^ThreeBusClassical$' --output-on-failure
else
  three_bus_status=""
fi

if [[ -n "${three_bus_build_status}" && "${three_bus_build_status}" -eq 0 &&
      -x "${three_bus_exe}" ]]; then
  run_step three_bus_metrics_status "${three_bus_metrics_log}" \
    bash -c 'cd "$1" && exec ./ThreeBusClassical' _ \
      "$(dirname "${three_bus_exe}")"
else
  three_bus_metrics_status=""
fi

three_bus_stats_line="$(
  extract_last_matching_line "${three_bus_metrics_log}" '^legacy KLU SUNDIALS stats:'
)"
three_bus_steps="$(extract_line_metric "${three_bus_stats_line}" "steps")"
three_bus_residual_evals="$(extract_line_metric "${three_bus_stats_line}" "residual_evals")"
three_bus_nonlinear_iters="$(extract_line_metric "${three_bus_stats_line}" "nonlinear_iters")"
three_bus_nonlinear_convergence_fails="$(extract_line_metric "${three_bus_stats_line}" "nonlinear_convergence_fails")"
three_bus_linear_decompositions="$(extract_line_metric "${three_bus_stats_line}" "linear_decompositions")"
three_bus_error_test_fails="$(extract_line_metric "${three_bus_stats_line}" "error_test_fails")"
three_bus_linear_iters="$(extract_line_metric "${three_bus_stats_line}" "linear_iters")"
three_bus_linear_conv_fails="$(extract_line_metric "${three_bus_stats_line}" "linear_conv_fails")"
three_bus_explicit_jacobian_evals="$(extract_line_metric "${three_bus_stats_line}" "explicit_jacobian_evals")"
three_bus_jac_times_setup_evals="$(extract_line_metric "${three_bus_stats_line}" "jac_times_setup_evals")"
three_bus_jac_times_evals="$(extract_line_metric "${three_bus_stats_line}" "jac_times_evals")"
three_bus_linear_residual_evals="$(extract_line_metric "${three_bus_stats_line}" "linear_residual_evals")"
three_bus_preconditioner_evals="$(extract_line_metric "${three_bus_stats_line}" "preconditioner_evals")"
three_bus_preconditioner_solves="$(extract_line_metric "${three_bus_stats_line}" "preconditioner_solves")"
three_bus_generated_jvp_configured="$(extract_line_metric "${three_bus_stats_line}" "generated_jvp_configured")"
three_bus_dense_no_enzyme_warnings="0"
three_bus_dense_missing_component_warnings="0"
if [[ -f "${three_bus_metrics_log}" ]]; then
  three_bus_dense_no_enzyme_warnings="$(
    grep -c "GridKit was not built with Enzyme" "${three_bus_metrics_log}" || true
  )"
  three_bus_dense_missing_component_warnings="$(
    grep -c "GridKit was built with Enzyme, but some models" "${three_bus_metrics_log}" || true
  )"
fi
three_bus_jacobian_path="enzyme_sparse"
if [[ "${three_bus_dense_no_enzyme_warnings}" =~ ^[0-9]+$ &&
      "${three_bus_dense_no_enzyme_warnings}" -gt 0 ]]; then
  three_bus_jacobian_path="dense_fallback_no_enzyme"
elif [[ "${three_bus_dense_missing_component_warnings}" =~ ^[0-9]+$ &&
        "${three_bus_dense_missing_component_warnings}" -gt 0 ]]; then
  three_bus_jacobian_path="dense_fallback_missing_component_jacobians"
fi

json_status() {
  local value="$1"
  if [[ -n "${value}" ]]; then
    printf '%s' "${value}"
  else
    printf 'null'
  fi
}

mkdir -p "$(dirname "${summary}")"
{
  printf '{\n'
  printf '  "sundials": {\n'
  printf '    "repo": %s,\n' "$(json_string "${sundials_repo}")"
  printf '    "tag": %s,\n' "$(json_string "${sundials_tag}")"
  printf '    "source": %s,\n' "$(json_string "${sundials_src}")"
  printf '    "build": %s,\n' "$(json_string "${sundials_build}")"
  printf '    "install": %s,\n' "$(json_string "${sundials_install}")"
  printf '    "klu_include_dir": %s,\n' "$(json_string "${klu_include_dir}")"
  printf '    "klu_library_dir": %s,\n' "$(json_string "${klu_library_dir}")"
  printf '    "configure_exit_code": %s,\n' "$(json_status "${sundials_config_status}")"
  printf '    "build_install_exit_code": %s,\n' "$(json_status "${sundials_build_status}")"
  printf '    "config_log": %s,\n' "$(json_string "${sundials_config_log}")"
  printf '    "build_install_log": %s\n' "$(json_string "${sundials_build_log}")"
  printf '  },\n'
  printf '  "gridkit": {\n'
  printf '    "build": %s,\n' "$(json_string "${gridkit_build}")"
  printf '    "enzyme_enabled": %s,\n' "$([[ "${gridkit_enable_enzyme}" == "ON" ]] && printf true || printf false)"
  printf '    "enzyme_dir": %s,\n' "$(json_string "${enzyme_dir}")"
  printf '    "configure_exit_code": %s,\n' "$(json_status "${gridkit_config_status}")"
  printf '    "test_ida_build_exit_code": %s,\n' "$(json_status "${test_ida_build_status}")"
  printf '    "test_ida_exit_code": %s,\n' "$(json_status "${test_ida_status}")"
  printf '    "three_bus_classical_build_exit_code": %s,\n' "$(json_status "${three_bus_build_status}")"
  printf '    "three_bus_classical_exit_code": %s,\n' "$(json_status "${three_bus_status}")"
  printf '    "three_bus_classical_metrics_exit_code": %s,\n' "$(json_status "${three_bus_metrics_status}")"
  printf '    "configure_log": %s,\n' "$(json_string "${gridkit_config_log}")"
  printf '    "test_ida_build_log": %s,\n' "$(json_string "${test_ida_build_log}")"
  printf '    "test_ida_log": %s,\n' "$(json_string "${test_ida_log}")"
  printf '    "three_bus_classical_build_log": %s,\n' "$(json_string "${three_bus_build_log}")"
  printf '    "three_bus_classical_log": %s,\n' "$(json_string "${three_bus_log}")"
  printf '    "three_bus_classical_executable": %s,\n' "$(json_string "${three_bus_exe}")"
  printf '    "three_bus_classical_metrics_log": %s\n' "$(json_string "${three_bus_metrics_log}")"
  printf '  },\n'
  printf '  "three_bus_classical_metrics": {\n'
  printf '    "line": %s,\n' "$(json_string "${three_bus_stats_line}")"
  printf '    "jacobian_path": %s,\n' "$(json_string "${three_bus_jacobian_path}")"
  printf '    "dense_no_enzyme_warning_count": %s,\n' "$(json_number_or_null "${three_bus_dense_no_enzyme_warnings}")"
  printf '    "dense_missing_component_warning_count": %s,\n' "$(json_number_or_null "${three_bus_dense_missing_component_warnings}")"
  printf '    "steps": %s,\n' "$(json_number_or_null "${three_bus_steps}")"
  printf '    "residual_evals": %s,\n' "$(json_number_or_null "${three_bus_residual_evals}")"
  printf '    "nonlinear_iters": %s,\n' "$(json_number_or_null "${three_bus_nonlinear_iters}")"
  printf '    "nonlinear_convergence_fails": %s,\n' "$(json_number_or_null "${three_bus_nonlinear_convergence_fails}")"
  printf '    "linear_decompositions": %s,\n' "$(json_number_or_null "${three_bus_linear_decompositions}")"
  printf '    "error_test_fails": %s,\n' "$(json_number_or_null "${three_bus_error_test_fails}")"
  printf '    "linear_iters": %s,\n' "$(json_number_or_null "${three_bus_linear_iters}")"
  printf '    "linear_conv_fails": %s,\n' "$(json_number_or_null "${three_bus_linear_conv_fails}")"
  printf '    "explicit_jacobian_evals": %s,\n' "$(json_number_or_null "${three_bus_explicit_jacobian_evals}")"
  printf '    "jac_times_setup_evals": %s,\n' "$(json_number_or_null "${three_bus_jac_times_setup_evals}")"
  printf '    "jac_times_evals": %s,\n' "$(json_number_or_null "${three_bus_jac_times_evals}")"
  printf '    "linear_residual_evals": %s,\n' "$(json_number_or_null "${three_bus_linear_residual_evals}")"
  printf '    "preconditioner_evals": %s,\n' "$(json_number_or_null "${three_bus_preconditioner_evals}")"
  printf '    "preconditioner_solves": %s,\n' "$(json_number_or_null "${three_bus_preconditioner_solves}")"
  printf '    "generated_jvp_configured": %s\n' "$(json_number_or_null "${three_bus_generated_jvp_configured}")"
  printf '  }\n'
  printf '}\n'
} > "${summary}"

echo "wrote ${summary}"

for status in \
  "${sundials_config_status}" \
  "${sundials_build_status}" \
  "${gridkit_config_status}" \
  "${test_ida_build_status}" \
  "${test_ida_status}" \
  "${three_bus_build_status}" \
  "${three_bus_status}" \
  "${three_bus_metrics_status}"; do
  if [[ -z "${status}" || "${status}" -ne 0 ]]; then
    echo "GridKit SUNDIALS IDA baseline failed; see ${summary}" >&2
    exit 1
  fi
done
