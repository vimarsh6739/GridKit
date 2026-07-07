#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
gridkit_root="$(cd "${script_dir}/.." && pwd)"
workspace_root="$(cd "${gridkit_root}/.." && pwd)"

out_dir="${1:-${gridkit_root}/build/reactant-jacobian-export/reactant}"
src="${gridkit_root}/examples/Experimental/ReactantJacobianRaise/GenClassicalSparseJacobianHarness.cpp"
ida_src="${gridkit_root}/examples/Experimental/ReactantJacobianRaise/GridKitIdaSparseHostHarness.cpp"
runtime_smoke_src="${gridkit_root}/examples/Experimental/ReactantJacobianRaise/GeneratedIdaRuntimeGlueSmokeHarness.cpp"

reactant_root="${REACTANT_ROOT:-${workspace_root}/Reactant/enzyme}"
reactant_cxx="${REACTANT_CXX:-${reactant_root}/bazel-bin/reactant-clang++}"
runtime_smoke_cxx="${GRIDKIT_REACTANT_RUNTIME_SMOKE_CXX:-${CXX:-$(command -v c++ || true)}}"
resource_dir="${REACTANT_RESOURCE_DIR:-}"
gridkit_build_include="${GRIDKIT_REACTANT_GRIDKIT_BUILD_INCLUDE:-${gridkit_root}/build/gridkit-enzyme-jvp-wrapper}"
sundials_shim_include="${gridkit_root}/examples/Experimental/ReactantJacobianRaise/sundials_shim/include"
export_ida_host="${GRIDKIT_REACTANT_EXPORT_IDA_HOST:-1}"

imported_mlir="${out_dir}/genclassical_reactant_imported.mlir"
printed_mlir="${out_dir}/genclassical_reactant_roundtrip_input.mlir"
object_file="${out_dir}/genclassical_reactant_roundtrip.o"
roundtrip_log="${out_dir}/genclassical_reactant_roundtrip.log"
summary="${out_dir}/genclassical_reactant_import_export.json"
enzymexlamlir_opt="${ENZYMEXLAMLIR_OPT:-${workspace_root}/Enzyme-JAX/bazel-bin/enzymexlamlir-opt}"
mlir_translate="${MLIR_TRANSLATE:-$(command -v mlir-translate || true)}"
llc_tool="${LLC:-$(command -v llc || true)}"
llvm_nm_tool="${LLVM_NM:-$(command -v llvm-nm || true)}"
marked_mlir="${out_dir}/genclassical_reactant_marked_sparse_jacobian.mlir"
marker_log="${out_dir}/genclassical_reactant_marker.log"

ida_imported_mlir="${out_dir}/gridkit_ida_host_reactant_imported.mlir"
ida_printed_mlir="${out_dir}/gridkit_ida_host_reactant_roundtrip_input.mlir"
ida_object_file="${out_dir}/gridkit_ida_host_reactant_roundtrip.o"
ida_roundtrip_log="${out_dir}/gridkit_ida_host_reactant_roundtrip.log"
ida_marked_mlir="${out_dir}/gridkit_ida_host_recovered_sundials.mlir"
ida_marker_log="${out_dir}/gridkit_ida_host_recovered_sundials.log"
bridge_mlir="${out_dir}/gridkit_semantic_bridge_matrix_free_input.mlir"
bridge_selected_mlir="${out_dir}/gridkit_semantic_bridge_matrix_free_selected.mlir"
bridge_log="${out_dir}/gridkit_semantic_bridge_matrix_free.log"
bridge_runtime_mlir="${out_dir}/gridkit_semantic_bridge_runtime_glue.mlir"
bridge_runtime_log="${out_dir}/gridkit_semantic_bridge_runtime_glue.log"
bridge_runtime_llvm_mlir="${out_dir}/gridkit_semantic_bridge_runtime_glue_llvm_only.mlir"
bridge_runtime_llvm_ir="${out_dir}/gridkit_semantic_bridge_runtime_glue.ll"
bridge_runtime_object="${out_dir}/gridkit_semantic_bridge_runtime_glue.o"
bridge_runtime_strip_log="${out_dir}/gridkit_semantic_bridge_runtime_glue_strip.log"
bridge_runtime_translate_log="${out_dir}/gridkit_semantic_bridge_runtime_glue_translate.log"
bridge_runtime_object_log="${out_dir}/gridkit_semantic_bridge_runtime_glue_object.log"
bridge_runtime_symbols="${out_dir}/gridkit_semantic_bridge_runtime_glue_symbols.txt"
bridge_runtime_smoke_exe="${out_dir}/gridkit_semantic_bridge_runtime_glue_smoke"
bridge_runtime_smoke_log="${out_dir}/gridkit_semantic_bridge_runtime_glue_smoke.log"

default_imported_mlir="${out_dir}/genclassical_reactant_default_imported.mlir"
default_object_file="${out_dir}/genclassical_reactant_default.o"
default_log="${out_dir}/genclassical_reactant_default.log"

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

json_string() {
  printf '"%s"' "$(json_escape "$1")"
}

count_lines() {
  if [[ -f "$1" ]]; then
    wc -l < "$1" | tr -d ' '
  else
    printf '0'
  fi
}

count_matches() {
  local pattern="$1"
  local file="$2"
  if [[ -f "${file}" ]]; then
    grep -cF "${pattern}" "${file}" || true
  else
    printf '0'
  fi
}

count_regex() {
  local pattern="$1"
  local file="$2"
  if [[ -f "${file}" ]]; then
    grep -cE "${pattern}" "${file}" || true
  else
    printf '0'
  fi
}

file_sha256() {
  if [[ -f "$1" ]]; then
    sha256sum "$1" | awk '{print $1}'
  fi
}

first_matching_line() {
  local pattern="$1"
  local file="$2"
  if [[ -f "${file}" ]]; then
    grep -m1 -F "${pattern}" "${file}" || true
  fi
}

first_matching_regex() {
  local pattern="$1"
  local file="$2"
  if [[ -f "${file}" ]]; then
    grep -m1 -E "${pattern}" "${file}" || true
  fi
}

extract_symbol_after() {
  local key="$1"
  local line="$2"
  printf '%s\n' "${line}" | sed -n "s/.*${key} = @\\([^ ]*\\).*/\\1/p"
}

extract_i64_attr() {
  local key="$1"
  local line="$2"
  printf '%s\n' "${line}" | sed -n "s/.*${key} = \\([0-9][0-9]*\\) : i64.*/\\1/p"
}

extract_string_attr() {
  local key="$1"
  local line="$2"
  printf '%s\n' "${line}" | sed -n "s/.*${key} = \"\\([^\"]*\\)\".*/\\1/p"
}

find_resource_dir() {
  local real_cxx
  real_cxx="$(readlink -f "${reactant_cxx}")"
  local bin_dir
  bin_dir="$(dirname "${real_cxx}")"
  local candidate
  for candidate in \
    "${bin_dir}/external/llvm-project/clang/staging" \
    "${bin_dir}/reactant-clang.runfiles/__main__/external/llvm-project/clang/staging" \
    "${bin_dir}/reactant-clang++.runfiles/__main__/external/llvm-project/clang/staging"; do
    if [[ -f "${candidate}/include/stddef.h" ]]; then
      printf '%s' "${candidate}"
      return 0
    fi
  done
  return 1
}

if [[ ! -x "${reactant_cxx}" ]]; then
  {
    echo "Reactant clang wrapper not found: ${reactant_cxx}"
    echo "Build it with:"
    echo "  (cd ${reactant_root} && bazel build --repo_env=CC=clang-18 --copt=-fbracket-depth=1024 --host_copt=-fbracket-depth=1024 -c dbg //:gen_reactant-clang++ //:reactant-clang)"
  } >&2
  exit 1
fi

if [[ -z "${resource_dir}" ]]; then
  if ! resource_dir="$(find_resource_dir)"; then
    {
      echo "Could not locate Reactant clang resource dir for ${reactant_cxx}"
      echo "Set REACTANT_RESOURCE_DIR to the directory containing include/stddef.h."
    } >&2
    exit 1
  fi
fi

mkdir -p "${out_dir}"

common_reactant_args=(
  -resource-dir "${resource_dir}"
  -std=c++20
  -O1
  -fno-discard-value-names
  -DGRIDKIT_ENABLE_ENZYME
  -I"${gridkit_root}"
  -I"${gridkit_root}/third-party/magic-enum/include"
  -Xclang -add-plugin -Xclang enzyme
  -mllvm -reactant-backend=cpu
)

reactant_args=(
  "${common_reactant_args[@]}"
  -c "${src}"
)

roundtrip_pipeline="print{filename=${printed_mlir}}"

set +e
(
  export OVERRIDE_PASS_PIPELINE="${roundtrip_pipeline}"
  export DEBUG_REACTANT_IMPORTED_MLIR_MOD_PATH="${imported_mlir}"
  exec "${reactant_cxx}" "${reactant_args[@]}" -o "${object_file}"
) > "${roundtrip_log}" 2>&1
roundtrip_status=$?
set -e

run_marker="${GRIDKIT_REACTANT_MARK_GRIDKIT_JACOBIAN:-1}"
marker_attempted="false"
marker_status=""
if [[ "${run_marker}" == "1" && -x "${enzymexlamlir_opt}" &&
      -f "${printed_mlir}" ]]; then
  marker_attempted="true"
  set +e
  "${enzymexlamlir_opt}" --recover-sundials-ida-llvm \
    --mark-gridkit-sparse-jacobian-llvm \
    --synthesize-sundials-ida-jacobian-actions \
    --select-sundials-ida-matrix-free \
    "${printed_mlir}" > "${marked_mlir}" 2> "${marker_log}"
  marker_status=$?
  set -e
fi

ida_attempted="false"
ida_skipped_reason=""
ida_roundtrip_status=""
ida_marker_attempted="false"
ida_marker_status=""
ida_roundtrip_pipeline="print{filename=${ida_printed_mlir}}"
if [[ "${export_ida_host}" == "1" ]]; then
  if [[ ! -f "${ida_src}" ]]; then
    ida_skipped_reason="IDA host harness not found"
  elif [[ ! -f "${gridkit_build_include}/GridKit/Definitions.hpp" ]]; then
    ida_skipped_reason="GridKit generated Definitions.hpp not found under GRIDKIT_REACTANT_GRIDKIT_BUILD_INCLUDE"
  elif [[ ! -d "${sundials_shim_include}" ]]; then
    ida_skipped_reason="SUNDIALS declaration shim include directory not found"
  else
    ida_attempted="true"
    ida_reactant_args=(
      "${common_reactant_args[@]}"
      -DGRIDKIT_ENABLE_SUNDIALS_SPARSE
      -I"${sundials_shim_include}"
      -I"${gridkit_build_include}"
      -c "${ida_src}"
    )

    set +e
    (
      export OVERRIDE_PASS_PIPELINE="${ida_roundtrip_pipeline}"
      export DEBUG_REACTANT_IMPORTED_MLIR_MOD_PATH="${ida_imported_mlir}"
      exec "${reactant_cxx}" "${ida_reactant_args[@]}" -o "${ida_object_file}"
    ) > "${ida_roundtrip_log}" 2>&1
    ida_roundtrip_status=$?
    set -e

    if [[ "${ida_roundtrip_status}" -eq 0 && -x "${enzymexlamlir_opt}" &&
          -f "${ida_printed_mlir}" ]]; then
      ida_marker_attempted="true"
      set +e
      "${enzymexlamlir_opt}" --recover-sundials-ida-llvm \
        --select-sundials-ida-matrix-free \
        "${ida_printed_mlir}" > "${ida_marked_mlir}" 2> "${ida_marker_log}"
      ida_marker_status=$?
      set -e
    fi
  fi
fi

bridge_attempted="false"
bridge_skipped_reason=""
bridge_status=""
bridge_runtime_attempted="false"
bridge_runtime_status=""
bridge_runtime_object_attempted="false"
bridge_runtime_object_skipped_reason=""
bridge_runtime_strip_status=""
bridge_runtime_translate_status=""
bridge_runtime_object_status=""
bridge_runtime_symbols_status=""
bridge_runtime_smoke_attempted="false"
bridge_runtime_smoke_skipped_reason=""
bridge_runtime_smoke_compile_status=""
bridge_runtime_smoke_run_status=""
if [[ -x "${enzymexlamlir_opt}" && -f "${marked_mlir}" &&
      -f "${ida_marked_mlir}" ]]; then
  materialization_line="$(first_matching_regex "enzymexla\\.jacobian_materialization .*source = \"DfDy\"" "${marked_mlir}")"
  dfdyp_materialization_line="$(first_matching_regex "enzymexla\\.jacobian_materialization .*source = \"DfDyp\"" "${marked_mlir}")"
  ida_solve_line="$(first_matching_line "enzymexla.sundials.ida_solve " "${ida_marked_mlir}")"

  bridge_materializer="$(extract_symbol_after "materializer" "${materialization_line}")"
  bridge_residual="$(extract_symbol_after "residual" "${materialization_line}")"
  bridge_dfdyp_materializer="$(extract_symbol_after "materializer" "${dfdyp_materialization_line}")"
  bridge_host_residual="$(extract_symbol_after "residual" "${ida_solve_line}")"
  bridge_host_jacobian="$(extract_symbol_after "jacobian" "${ida_solve_line}")"
  bridge_host_source_function="$(extract_string_attr "source_function" "${ida_solve_line}")"
  bridge_host_linear_solver_source_function="$(extract_string_attr "linear_solver_source_function" "${ida_solve_line}")"
  bridge_host_jacobian_registration_source_function="$(extract_string_attr "jacobian_registration_source_function" "${ida_solve_line}")"

  if [[ -z "${materialization_line}" || -z "${dfdyp_materialization_line}" ||
        -z "${ida_solve_line}" ]]; then
    bridge_skipped_reason="missing DfDy/DfDyp sparse materialization or recovered IDA solve"
  elif [[ -z "${bridge_materializer}" || -z "${bridge_dfdyp_materializer}" ||
          -z "${bridge_residual}" ]]; then
    bridge_skipped_reason="could not parse sparse materializer, DfDyp materializer, or residual symbol"
  else
    bridge_attempted="true"
    set +e
    awk -v residual="${bridge_residual}" \
        -v materializer="${bridge_materializer}" \
        -v host_residual="${bridge_host_residual}" \
        -v host_jacobian="${bridge_host_jacobian}" \
        -v host_source="${bridge_host_source_function}" \
        -v host_linear_solver_source="${bridge_host_linear_solver_source_function}" \
        -v host_jacobian_registration_source="${bridge_host_jacobian_registration_source_function}" '
      !inserted && /^module/ {
        print
        print "  enzymexla.sundials.ida_solve residual = @" residual
        print "    jacobian = @" materializer
        print "    linear_solver = <explicit_sparse_direct>"
        print "    jacobian_demand = <explicit_matrix>"
        print "    () {bridge_host_jacobian_callback = \"" host_jacobian "\", bridge_host_jacobian_registration_source_function = \"" host_jacobian_registration_source "\", bridge_host_linear_solver_source_function = \"" host_linear_solver_source "\", bridge_host_residual_callback = \"" host_residual "\", bridge_host_source_function = \"" host_source "\", enzymexla.sundials.allow_matrix_free, source = \"gridkit_semantic_bridge\"} : () -> ()"
        inserted = 1
        next
      }
      { print }
    ' "${marked_mlir}" > "${bridge_mlir}"
    awk_status=$?
    set -e

    if [[ "${awk_status}" -eq 0 ]]; then
      set +e
      "${enzymexlamlir_opt}" --synthesize-sundials-ida-jacobian-actions \
        --select-sundials-ida-matrix-free \
        "${bridge_mlir}" > "${bridge_selected_mlir}" 2> "${bridge_log}"
      bridge_status=$?
      set -e
      if [[ "${bridge_status}" -eq 0 && -f "${bridge_selected_mlir}" ]]; then
        bridge_runtime_attempted="true"
        set +e
        "${enzymexlamlir_opt}" --emit-sundials-ida-runtime-glue-llvm \
          "${bridge_selected_mlir}" > "${bridge_runtime_mlir}" 2> "${bridge_runtime_log}"
        bridge_runtime_status=$?
        set -e
        if [[ "${bridge_runtime_status}" -eq 0 && -f "${bridge_runtime_mlir}" ]]; then
          if [[ ! -x "${mlir_translate}" ]]; then
            bridge_runtime_object_skipped_reason="mlir-translate not found; set MLIR_TRANSLATE"
          elif [[ ! -x "${llc_tool}" ]]; then
            bridge_runtime_object_skipped_reason="llc not found; set LLC"
          else
            bridge_runtime_object_attempted="true"
            set +e
            "${enzymexlamlir_opt}" --strip-sundials-ida-runtime-glue-metadata \
              "${bridge_runtime_mlir}" > "${bridge_runtime_llvm_mlir}" 2> "${bridge_runtime_strip_log}"
            bridge_runtime_strip_status=$?
            set -e

            if [[ "${bridge_runtime_strip_status}" -eq 0 ]]; then
              set +e
              "${mlir_translate}" --mlir-to-llvmir \
                "${bridge_runtime_llvm_mlir}" -o "${bridge_runtime_llvm_ir}" \
                > "${bridge_runtime_translate_log}" 2>&1
              bridge_runtime_translate_status=$?
              set -e
            fi

            if [[ "${bridge_runtime_translate_status}" -eq 0 ]]; then
              set +e
              "${llc_tool}" -function-sections -data-sections -filetype=obj \
                "${bridge_runtime_llvm_ir}" \
                -o "${bridge_runtime_object}" > "${bridge_runtime_object_log}" 2>&1
              bridge_runtime_object_status=$?
              set -e
            fi

            if [[ "${bridge_runtime_object_status}" -eq 0 &&
                  -f "${bridge_runtime_object}" && -x "${llvm_nm_tool}" ]]; then
              set +e
              "${llvm_nm_tool}" -g --defined-only "${bridge_runtime_object}" \
                > "${bridge_runtime_symbols}" 2>> "${bridge_runtime_object_log}"
              bridge_runtime_symbols_status=$?
              set -e
            fi

            if [[ "${bridge_runtime_object_status}" -eq 0 &&
                  -f "${bridge_runtime_object}" ]]; then
              if [[ ! -f "${runtime_smoke_src}" ]]; then
                bridge_runtime_smoke_skipped_reason="generated runtime glue smoke harness not found"
              elif [[ -z "${runtime_smoke_cxx}" || ! -x "${runtime_smoke_cxx}" ]]; then
                bridge_runtime_smoke_skipped_reason="C++ compiler not found; set GRIDKIT_REACTANT_RUNTIME_SMOKE_CXX or CXX"
              else
                bridge_runtime_smoke_attempted="true"
                set +e
                "${runtime_smoke_cxx}" -std=c++20 -O0 -g -pthread \
                  -ffunction-sections -fdata-sections \
                  -I"${gridkit_root}" \
                  "${runtime_smoke_src}" \
                  "${gridkit_root}/GridKit/Solver/Dynamic/IdaJvpRuntime.cpp" \
                  "${bridge_runtime_object}" \
                  -Wl,--gc-sections -no-pie \
                  -o "${bridge_runtime_smoke_exe}" \
                  > "${bridge_runtime_smoke_log}" 2>&1
                bridge_runtime_smoke_compile_status=$?
                set -e

                if [[ "${bridge_runtime_smoke_compile_status}" -eq 0 ]]; then
                  set +e
                  "${bridge_runtime_smoke_exe}" >> "${bridge_runtime_smoke_log}" 2>&1
                  bridge_runtime_smoke_run_status=$?
                  set -e
                fi
              fi
            fi
          fi
        fi
      fi
    else
      bridge_status="${awk_status}"
    fi
  fi
fi

try_default="${GRIDKIT_REACTANT_TRY_DEFAULT:-0}"
default_status=""
if [[ "${try_default}" == "1" ]]; then
  set +e
  {
    (
      export DEBUG_REACTANT_IMPORTED_MLIR_MOD_PATH="${default_imported_mlir}"
      exec "${reactant_cxx}" "${reactant_args[@]}" -o "${default_object_file}"
    ) > "${default_log}" 2>&1
    default_status=$?
  } 2>/dev/null
  set -e
fi

if [[ -n "${marker_status}" ]]; then
  marker_exit_json="${marker_status}"
else
  marker_exit_json="null"
fi
if [[ -n "${ida_roundtrip_status}" ]]; then
  ida_roundtrip_exit_json="${ida_roundtrip_status}"
else
  ida_roundtrip_exit_json="null"
fi
if [[ -n "${ida_marker_status}" ]]; then
  ida_marker_exit_json="${ida_marker_status}"
else
  ida_marker_exit_json="null"
fi
if [[ -n "${bridge_status}" ]]; then
  bridge_exit_json="${bridge_status}"
else
  bridge_exit_json="null"
fi
if [[ -n "${bridge_runtime_status}" ]]; then
  bridge_runtime_exit_json="${bridge_runtime_status}"
else
  bridge_runtime_exit_json="null"
fi
if [[ -n "${bridge_runtime_strip_status}" ]]; then
  bridge_runtime_strip_exit_json="${bridge_runtime_strip_status}"
else
  bridge_runtime_strip_exit_json="null"
fi
if [[ -n "${bridge_runtime_translate_status}" ]]; then
  bridge_runtime_translate_exit_json="${bridge_runtime_translate_status}"
else
  bridge_runtime_translate_exit_json="null"
fi
if [[ -n "${bridge_runtime_object_status}" ]]; then
  bridge_runtime_object_exit_json="${bridge_runtime_object_status}"
else
  bridge_runtime_object_exit_json="null"
fi
if [[ -n "${bridge_runtime_symbols_status}" ]]; then
  bridge_runtime_symbols_exit_json="${bridge_runtime_symbols_status}"
else
  bridge_runtime_symbols_exit_json="null"
fi
if [[ -n "${bridge_runtime_smoke_compile_status}" ]]; then
  bridge_runtime_smoke_compile_exit_json="${bridge_runtime_smoke_compile_status}"
else
  bridge_runtime_smoke_compile_exit_json="null"
fi
if [[ -n "${bridge_runtime_smoke_run_status}" ]]; then
  bridge_runtime_smoke_run_exit_json="${bridge_runtime_smoke_run_status}"
else
  bridge_runtime_smoke_run_exit_json="null"
fi
if [[ -n "${default_status}" ]]; then
  default_exit_json="${default_status}"
else
  default_exit_json="null"
fi

printf '{\n' > "${summary}"
printf '  "source": %s,\n' "$(json_string "${src}")" >> "${summary}"
printf '  "reactant_clang": %s,\n' "$(json_string "${reactant_cxx}")" >> "${summary}"
printf '  "resource_dir": %s,\n' "$(json_string "${resource_dir}")" >> "${summary}"
printf '  "override_pass_pipeline": %s,\n' "$(json_string "${roundtrip_pipeline}")" >> "${summary}"
printf '  "roundtrip": {\n' >> "${summary}"
printf '    "exit_code": %s,\n' "${roundtrip_status}" >> "${summary}"
printf '    "object_created": %s,\n' "$([[ -f "${object_file}" ]] && printf true || printf false)" >> "${summary}"
printf '    "imported_mlir": %s,\n' "$(json_string "${imported_mlir}")" >> "${summary}"
printf '    "printed_mlir": %s,\n' "$(json_string "${printed_mlir}")" >> "${summary}"
printf '    "object": %s,\n' "$(json_string "${object_file}")" >> "${summary}"
printf '    "log": %s\n' "$(json_string "${roundtrip_log}")" >> "${summary}"
printf '  },\n' >> "${summary}"
printf '  "marker": {\n' >> "${summary}"
printf '    "attempted": %s,\n' "${marker_attempted}" >> "${summary}"
printf '    "exit_code": %s,\n' "${marker_exit_json}" >> "${summary}"
printf '    "tool": %s,\n' "$(json_string "${enzymexlamlir_opt}")" >> "${summary}"
printf '    "marked_mlir": %s,\n' "$(json_string "${marked_mlir}")" >> "${summary}"
printf '    "log": %s\n' "$(json_string "${marker_log}")" >> "${summary}"
printf '  },\n' >> "${summary}"
printf '  "ida_host": {\n' >> "${summary}"
printf '    "attempted": %s,\n' "${ida_attempted}" >> "${summary}"
printf '    "enabled": %s,\n' "$([[ "${export_ida_host}" == "1" ]] && printf true || printf false)" >> "${summary}"
printf '    "skipped_reason": %s,\n' "$(json_string "${ida_skipped_reason}")" >> "${summary}"
printf '    "source": %s,\n' "$(json_string "${ida_src}")" >> "${summary}"
printf '    "gridkit_build_include": %s,\n' "$(json_string "${gridkit_build_include}")" >> "${summary}"
printf '    "sundials_shim_include": %s,\n' "$(json_string "${sundials_shim_include}")" >> "${summary}"
printf '    "override_pass_pipeline": %s,\n' "$(json_string "${ida_roundtrip_pipeline}")" >> "${summary}"
printf '    "roundtrip_exit_code": %s,\n' "${ida_roundtrip_exit_json}" >> "${summary}"
printf '    "object_created": %s,\n' "$([[ -f "${ida_object_file}" ]] && printf true || printf false)" >> "${summary}"
printf '    "imported_mlir": %s,\n' "$(json_string "${ida_imported_mlir}")" >> "${summary}"
printf '    "printed_mlir": %s,\n' "$(json_string "${ida_printed_mlir}")" >> "${summary}"
printf '    "object": %s,\n' "$(json_string "${ida_object_file}")" >> "${summary}"
printf '    "roundtrip_log": %s,\n' "$(json_string "${ida_roundtrip_log}")" >> "${summary}"
printf '    "marker_attempted": %s,\n' "${ida_marker_attempted}" >> "${summary}"
printf '    "marker_exit_code": %s,\n' "${ida_marker_exit_json}" >> "${summary}"
printf '    "marked_mlir": %s,\n' "$(json_string "${ida_marked_mlir}")" >> "${summary}"
printf '    "marker_log": %s\n' "$(json_string "${ida_marker_log}")" >> "${summary}"
printf '  },\n' >> "${summary}"
printf '  "semantic_bridge": {\n' >> "${summary}"
printf '    "attempted": %s,\n' "${bridge_attempted}" >> "${summary}"
printf '    "skipped_reason": %s,\n' "$(json_string "${bridge_skipped_reason}")" >> "${summary}"
printf '    "exit_code": %s,\n' "${bridge_exit_json}" >> "${summary}"
printf '    "runtime_attempted": %s,\n' "${bridge_runtime_attempted}" >> "${summary}"
printf '    "runtime_exit_code": %s,\n' "${bridge_runtime_exit_json}" >> "${summary}"
printf '    "runtime_object_attempted": %s,\n' "${bridge_runtime_object_attempted}" >> "${summary}"
printf '    "runtime_object_skipped_reason": %s,\n' "$(json_string "${bridge_runtime_object_skipped_reason}")" >> "${summary}"
printf '    "runtime_strip_exit_code": %s,\n' "${bridge_runtime_strip_exit_json}" >> "${summary}"
printf '    "runtime_translate_exit_code": %s,\n' "${bridge_runtime_translate_exit_json}" >> "${summary}"
printf '    "runtime_object_exit_code": %s,\n' "${bridge_runtime_object_exit_json}" >> "${summary}"
printf '    "runtime_symbols_exit_code": %s,\n' "${bridge_runtime_symbols_exit_json}" >> "${summary}"
printf '    "runtime_smoke_attempted": %s,\n' "${bridge_runtime_smoke_attempted}" >> "${summary}"
printf '    "runtime_smoke_skipped_reason": %s,\n' "$(json_string "${bridge_runtime_smoke_skipped_reason}")" >> "${summary}"
printf '    "runtime_smoke_compile_exit_code": %s,\n' "${bridge_runtime_smoke_compile_exit_json}" >> "${summary}"
printf '    "runtime_smoke_run_exit_code": %s,\n' "${bridge_runtime_smoke_run_exit_json}" >> "${summary}"
printf '    "input_mlir": %s,\n' "$(json_string "${bridge_mlir}")" >> "${summary}"
printf '    "selected_mlir": %s,\n' "$(json_string "${bridge_selected_mlir}")" >> "${summary}"
printf '    "runtime_mlir": %s,\n' "$(json_string "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "runtime_llvm_mlir": %s,\n' "$(json_string "${bridge_runtime_llvm_mlir}")" >> "${summary}"
printf '    "runtime_llvm_ir": %s,\n' "$(json_string "${bridge_runtime_llvm_ir}")" >> "${summary}"
printf '    "runtime_object": %s,\n' "$(json_string "${bridge_runtime_object}")" >> "${summary}"
printf '    "runtime_symbols": %s,\n' "$(json_string "${bridge_runtime_symbols}")" >> "${summary}"
printf '    "runtime_smoke_executable": %s,\n' "$(json_string "${bridge_runtime_smoke_exe}")" >> "${summary}"
printf '    "runtime_smoke_harness": %s,\n' "$(json_string "${runtime_smoke_src}")" >> "${summary}"
printf '    "mlir_translate": %s,\n' "$(json_string "${mlir_translate}")" >> "${summary}"
printf '    "llc": %s,\n' "$(json_string "${llc_tool}")" >> "${summary}"
printf '    "llvm_nm": %s,\n' "$(json_string "${llvm_nm_tool}")" >> "${summary}"
printf '    "runtime_smoke_cxx": %s,\n' "$(json_string "${runtime_smoke_cxx}")" >> "${summary}"
printf '    "log": %s,\n' "$(json_string "${bridge_log}")" >> "${summary}"
printf '    "runtime_log": %s,\n' "$(json_string "${bridge_runtime_log}")" >> "${summary}"
printf '    "runtime_strip_log": %s,\n' "$(json_string "${bridge_runtime_strip_log}")" >> "${summary}"
printf '    "runtime_translate_log": %s,\n' "$(json_string "${bridge_runtime_translate_log}")" >> "${summary}"
printf '    "runtime_object_log": %s,\n' "$(json_string "${bridge_runtime_object_log}")" >> "${summary}"
printf '    "runtime_smoke_log": %s\n' "$(json_string "${bridge_runtime_smoke_log}")" >> "${summary}"
printf '  },\n' >> "${summary}"
printf '  "default_pipeline": {\n' >> "${summary}"
printf '    "attempted": %s,\n' "$([[ "${try_default}" == "1" ]] && printf true || printf false)" >> "${summary}"
printf '    "exit_code": %s,\n' "${default_exit_json}" >> "${summary}"
printf '    "imported_mlir": %s,\n' "$(json_string "${default_imported_mlir}")" >> "${summary}"
printf '    "object": %s,\n' "$(json_string "${default_object_file}")" >> "${summary}"
printf '    "log": %s\n' "$(json_string "${default_log}")" >> "${summary}"
printf '  },\n' >> "${summary}"
printf '  "line_counts": {\n' >> "${summary}"
printf '    "imported_mlir": %s,\n' "$(count_lines "${imported_mlir}")" >> "${summary}"
printf '    "printed_mlir": %s,\n' "$(count_lines "${printed_mlir}")" >> "${summary}"
printf '    "marked_mlir": %s,\n' "$(count_lines "${marked_mlir}")" >> "${summary}"
printf '    "ida_host_imported_mlir": %s,\n' "$(count_lines "${ida_imported_mlir}")" >> "${summary}"
printf '    "ida_host_printed_mlir": %s,\n' "$(count_lines "${ida_printed_mlir}")" >> "${summary}"
printf '    "ida_host_marked_mlir": %s,\n' "$(count_lines "${ida_marked_mlir}")" >> "${summary}"
printf '    "semantic_bridge_input_mlir": %s,\n' "$(count_lines "${bridge_mlir}")" >> "${summary}"
printf '    "semantic_bridge_selected_mlir": %s,\n' "$(count_lines "${bridge_selected_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_mlir": %s,\n' "$(count_lines "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_llvm_mlir": %s,\n' "$(count_lines "${bridge_runtime_llvm_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_llvm_ir": %s\n' "$(count_lines "${bridge_runtime_llvm_ir}")" >> "${summary}"
printf '  },\n' >> "${summary}"
printf '  "matching_lines": {\n' >> "${summary}"
printf '    "__enzyme_fwddiff": %s,\n' "$(count_matches "__enzyme_fwddiff" "${printed_mlir}")" >> "${summary}"
printf '    "__enzyme_todense": %s,\n' "$(count_matches "__enzyme_todense" "${printed_mlir}")" >> "${summary}"
printf '    "sparse_store": %s,\n' "$(count_matches "sparse_store" "${printed_mlir}")" >> "${summary}"
printf '    "gridkit_genclassical_existing_sparse_jacobian": %s,\n' "$(count_matches "gridkit_genclassical_existing_sparse_jacobian" "${printed_mlir}")" >> "${summary}"
printf '    "DfDy": %s,\n' "$(count_matches "DfDy" "${printed_mlir}")" >> "${summary}"
printf '    "DfDyp": %s,\n' "$(count_matches "DfDyp" "${printed_mlir}")" >> "${summary}"
printf '    "DfDwb": %s,\n' "$(count_matches "DfDwb" "${printed_mlir}")" >> "${summary}"
printf '    "DhDy": %s,\n' "$(count_matches "DhDy" "${printed_mlir}")" >> "${summary}"
printf '    "IDAInit": %s,\n' "$(count_matches "IDAInit" "${ida_printed_mlir}")" >> "${summary}"
printf '    "IDASetJacFn": %s,\n' "$(count_matches "IDASetJacFn" "${ida_printed_mlir}")" >> "${summary}"
printf '    "IDASetLinearSolver": %s,\n' "$(count_matches "IDASetLinearSolver" "${ida_printed_mlir}")" >> "${summary}"
printf '    "SUNLinSol_KLU": %s,\n' "$(count_matches "SUNLinSol_KLU" "${ida_printed_mlir}")" >> "${summary}"
printf '    "gridkit_ida_existing_sparse_solver_configuration": %s\n' "$(count_matches "gridkit_ida_existing_sparse_solver_configuration" "${ida_printed_mlir}")" >> "${summary}"
printf '  },\n' >> "${summary}"
printf '  "marked_attributes": {\n' >> "${summary}"
printf '    "semantic_jacobian_materializations": %s,\n' "$(count_matches "enzymexla.jacobian_materialization" "${marked_mlir}")" >> "${summary}"
printf '    "semantic_jacobian_materializations_with_residual": %s,\n' "$(count_regex "enzymexla\\.jacobian_materialization .* residual = @" "${marked_mlir}")" >> "${summary}"
printf '    "semantic_jacobian_materializations_with_activity": %s,\n' "$(count_regex "enzymexla\\.jacobian_materialization .*enzyme_activity = \\[" "${marked_mlir}")" >> "${summary}"
printf '    "semantic_jacobian_materializations_with_structured_activity": %s,\n' "$(count_regex "enzymexla\\.jacobian_materialization .*input_activity = \\[" "${marked_mlir}")" >> "${summary}"
printf '    "semantic_jacobian_materializations_with_active_input": %s,\n' "$(count_regex "enzymexla\\.jacobian_materialization .*active_input_index =" "${marked_mlir}")" >> "${summary}"
printf '    "semantic_jacobian_materializations_with_dimension_args": %s,\n' "$(count_regex "enzymexla\\.jacobian_materialization .*output_dimension_arg =" "${marked_mlir}")" >> "${summary}"
printf '    "semantic_jacobian_materializations_with_sparse_layout": %s,\n' "$(count_regex "enzymexla\\.jacobian_materialization .*sparse_assembly =" "${marked_mlir}")" >> "${summary}"
printf '    "semantic_jacobian_materializations_with_sparse_buffers": %s,\n' "$(count_regex "enzymexla\\.jacobian_materialization .*sparse_values_arg =" "${marked_mlir}")" >> "${summary}"
printf '    "semantic_jacobian_actions": %s,\n' "$(count_regex "enzymexla\\.jacobian_action " "${marked_mlir}")" >> "${summary}"
printf '    "semantic_jacobian_actions_with_materialization": %s,\n' "$(count_regex "enzymexla\\.jacobian_action .*materialization = @" "${marked_mlir}")" >> "${summary}"
printf '    "semantic_jacobian_actions_with_sparse_layout": %s,\n' "$(count_regex "enzymexla\\.jacobian_action .*sparse_assembly =" "${marked_mlir}")" >> "${summary}"
printf '    "semantic_jacobian_actions_synthesized_attr": %s,\n' "$(count_matches "enzymexla.jacobian_actions_synthesized" "${marked_mlir}")" >> "${summary}"
printf '    "sundials_ida_matrix_free_selected_attr": %s,\n' "$(count_matches "enzymexla.sundials.ida_matrix_free_selected" "${marked_mlir}")" >> "${summary}"
printf '    "semantic_sundials_ida_solves": %s,\n' "$(count_regex "enzymexla\\.sundials\\.ida_solve[[:space:]]" "${marked_mlir}")" >> "${summary}"
printf '    "semantic_sundials_ida_solves_recovered_attr": %s,\n' "$(count_matches "enzymexla.sundials.ida_solves_recovered" "${marked_mlir}")" >> "${summary}"
printf '    "semantic_sundials_ida_explicit_matrix_solves": %s,\n' "$(count_regex "enzymexla\\.sundials\\.ida_solve .*jacobian_demand = <explicit_matrix>" "${marked_mlir}")" >> "${summary}"
printf '    "semantic_sundials_ida_jacobian_action_solves": %s,\n' "$(count_regex "enzymexla\\.sundials\\.ida_solve .*jacobian_demand = <jacobian_action>" "${marked_mlir}")" >> "${summary}"
printf '    "sundials_ida_solves_linked_jacobian_actions_attr": %s,\n' "$(count_matches "enzymexla.sundials.ida_solves_linked_jacobian_actions" "${marked_mlir}")" >> "${summary}"
printf '    "marked_sparse_helpers_attr": %s,\n' "$(count_matches "gridkit.jacobian.marked_sparse_helpers" "${marked_mlir}")" >> "${summary}"
printf '    "materialized_helpers": %s,\n' "$(count_matches "gridkit.jacobian.materialization" "${marked_mlir}")" >> "${summary}"
printf '    "residual_jvp_candidates": %s,\n' "$(count_matches "gridkit.jacobian.action" "${marked_mlir}")" >> "${summary}"
printf '    "sparse_todense_roles": %s,\n' "$(count_matches "gridkit.jacobian.role" "${marked_mlir}")" >> "${summary}"
printf '    "ida_jac_times_markers": %s,\n' "$(count_matches "gridkit.solver" "${marked_mlir}")" >> "${summary}"
printf '    "ida_host_semantic_sundials_ida_solves": %s,\n' "$(count_regex "enzymexla\\.sundials\\.ida_solve[[:space:]]" "${ida_marked_mlir}")" >> "${summary}"
printf '    "ida_host_semantic_sundials_ida_explicit_matrix_solves": %s,\n' "$(count_regex "enzymexla\\.sundials\\.ida_solve .*jacobian_demand = <explicit_matrix>" "${ida_marked_mlir}")" >> "${summary}"
printf '    "ida_host_semantic_sundials_ida_jacobian_action_solves": %s,\n' "$(count_regex "enzymexla\\.sundials\\.ida_solve .*jacobian_demand = <jacobian_action>" "${ida_marked_mlir}")" >> "${summary}"
printf '    "ida_host_matrix_free_selected_attr": %s,\n' "$(count_matches "enzymexla.sundials.ida_matrix_free_selected" "${ida_marked_mlir}")" >> "${summary}"
printf '    "ida_host_recovered_attr": %s,\n' "$(count_matches "enzymexla.sundials.ida_solves_recovered" "${ida_marked_mlir}")" >> "${summary}"
printf '    "ida_host_user_data_registered_attrs": %s,\n' "$(count_matches "enzymexla.sundials.user_data_registered" "${ida_marked_mlir}")" >> "${summary}"
printf '    "ida_host_user_data_registration_roles": %s,\n' "$(count_matches "ida_user_data_registration" "${ida_marked_mlir}")" >> "${summary}"
printf '    "ida_host_user_data_unwrap_calls": %s,\n' "$(count_matches "unwrapIdaUserDataModel" "${ida_printed_mlir}")" >> "${summary}"
printf '    "ida_host_sparse_direct_roles": %s,\n' "$(count_matches "ida_sparse_direct_linear_solver" "${ida_marked_mlir}")" >> "${summary}"
printf '    "ida_host_jacobian_registration_roles": %s,\n' "$(count_matches "ida_jacobian_registration" "${ida_marked_mlir}")" >> "${summary}"
printf '    "ida_host_linear_solver_source_function_attrs": %s,\n' "$(count_matches "linear_solver_source_function" "${ida_marked_mlir}")" >> "${summary}"
printf '    "ida_host_jacobian_registration_source_function_attrs": %s,\n' "$(count_matches "jacobian_registration_source_function" "${ida_marked_mlir}")" >> "${summary}"
printf '    "ida_host_jvp_setup_yy_template_operand_attrs": %s,\n' "$(count_matches "jvp_setup_yy_template_operand" "${ida_marked_mlir}")" >> "${summary}"
printf '    "ida_host_jvp_setup_sunctx_operand_attrs": %s,\n' "$(count_matches "jvp_setup_sunctx_operand" "${ida_marked_mlir}")" >> "${summary}"
printf '    "ida_host_jvp_setup_ida_mem_operand_attrs": %s,\n' "$(count_matches "jvp_setup_ida_mem_operand" "${ida_marked_mlir}")" >> "${summary}"
printf '    "ida_host_jvp_setup_model_operand_attrs": %s,\n' "$(count_matches "jvp_setup_model_operand" "${ida_marked_mlir}")" >> "${summary}"
printf '    "semantic_bridge_ida_solves": %s,\n' "$(count_regex "enzymexla\\.sundials\\.ida_solve[[:space:]]" "${bridge_selected_mlir}")" >> "${summary}"
printf '    "semantic_bridge_jacobian_action_solves": %s,\n' "$(count_regex "enzymexla\\.sundials\\.ida_solve .*jacobian_demand = <jacobian_action>" "${bridge_selected_mlir}")" >> "${summary}"
printf '    "semantic_bridge_matrix_free_selected_attr": %s,\n' "$(count_matches "enzymexla.sundials.ida_matrix_free_selected" "${bridge_selected_mlir}")" >> "${summary}"
printf '    "semantic_bridge_allow_matrix_free_attrs": %s,\n' "$(count_matches "enzymexla.sundials.allow_matrix_free" "${bridge_selected_mlir}")" >> "${summary}"
printf '    "semantic_bridge_host_linear_solver_source_attrs": %s,\n' "$(count_matches "bridge_host_linear_solver_source_function" "${bridge_selected_mlir}")" >> "${summary}"
printf '    "semantic_bridge_host_jacobian_registration_source_attrs": %s,\n' "$(count_matches "bridge_host_jacobian_registration_source_function" "${bridge_selected_mlir}")" >> "${summary}"
printf '    "semantic_bridge_effective_jacobian_actions_synthesized_attr": %s,\n' "$(count_matches "enzymexla.sundials.ida_effective_jacobian_actions_synthesized" "${bridge_selected_mlir}")" >> "${summary}"
printf '    "semantic_bridge_effective_jacobian_actions": %s,\n' "$(count_matches "enzymexla.sundials.ida_effective_jacobian_action," "${bridge_selected_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_glue_emitted_attr": %s,\n' "$(count_matches "enzymexla.sundials.ida_runtime_glue_emitted" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_jvp_kernel_adapters_emitted_attr": %s,\n' "$(count_matches "enzymexla.sundials.ida_jvp_kernel_adapters_emitted" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_raw_jvp_kernels_emitted_attr": %s,\n' "$(count_matches "enzymexla.sundials.ida_raw_jvp_kernels_emitted" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_lowered_raw_jvp_kernels_linked_attr": %s,\n' "$(count_matches "enzymexla.sundials.ida_lowered_raw_jvp_kernels_linked" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_host_splices_emitted_attr": %s,\n' "$(count_matches "enzymexla.sundials.ida_host_splices_emitted" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_host_splice_dispatchers_emitted_attr": %s,\n' "$(count_matches "enzymexla.sundials.ida_host_splice_dispatchers_emitted" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_host_splice_records": %s,\n' "$(count_regex "enzymexla\\.sundials\\.ida_host_splice[[:space:]]" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_host_splice_plan_roles": %s,\n' "$(count_matches "ida_jvp_host_splice_plan" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_host_splice_attrs": %s,\n' "$(count_matches "enzymexla.sundials.runtime_host_splice" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_host_setup_dispatcher_attrs": %s,\n' "$(count_matches "enzymexla.sundials.runtime_host_setup_dispatcher" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_host_teardown_dispatcher_attrs": %s,\n' "$(count_matches "enzymexla.sundials.runtime_host_teardown_dispatcher" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_host_setup_dispatcher_functions": %s,\n' "$(count_matches "ida_jvp_host_setup_dispatcher" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_host_teardown_dispatcher_functions": %s,\n' "$(count_matches "ida_jvp_host_teardown_dispatcher" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_host_setup_dispatch_calls": %s,\n' "$(count_matches "enzymexla.sundials.role = \"ida_jvp_host_setup_dispatch\"" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_host_teardown_dispatch_calls": %s,\n' "$(count_matches "enzymexla.sundials.role = \"ida_jvp_host_teardown_dispatch\"" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_jactimes_callbacks": %s,\n' "$(count_matches "ida_jactimes_callback" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_registrations": %s,\n' "$(count_matches "ida_jactimes_registration" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_context_setup_functions": %s,\n' "$(count_matches "ida_jvp_context_setup" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_context_teardown_functions": %s,\n' "$(count_matches "ida_jvp_context_teardown" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_context_owner_registry_attrs": %s,\n' "$(count_matches "context_owner_registry" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_context_teardown_ida_mem_attrs": %s,\n' "$(count_matches "teardown_argument = \"ida_mem\"" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_host_linear_solver_source_attrs": %s,\n' "$(count_matches "host_linear_solver_source_function" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_host_jacobian_registration_source_attrs": %s,\n' "$(count_matches "host_jacobian_registration_source_function" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_host_configure_source_attrs": %s,\n' "$(count_matches "host_configure_source_function" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_placeholder_callbacks": %s,\n' "$(count_matches "enzymexla.sundials.callback_body = \"placeholder\"" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_delegating_callbacks": %s,\n' "$(count_matches "enzymexla.sundials.callback_body = \"delegates_jvp_kernel\"" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_jvp_kernel_adapters": %s,\n' "$(count_matches "enzymexla.sundials.runtime_role = \"ida_jvp_kernel_adapter\"" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_jvp_kernel_adapters_unpack_nvector": %s,\n' "$(count_matches "nvector_unpack_and_raw_jvp_call" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_jvp_kernels_require_lowering": %s,\n' "$(count_matches "semantic_raw_kernel_requires_lowering" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_jvp_kernel_attrs": %s,\n' "$(count_matches "enzymexla.sundials.runtime_jvp_kernel" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_raw_jvp_kernels": %s,\n' "$(count_matches "enzymexla.sundials.runtime_role = \"ida_raw_jvp_kernel\"" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_raw_jvp_kernel_calls": %s,\n' "$(count_regex "llvm\\.call @__enzymexla_sundials_ida_raw_jvp_kernel_" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_raw_jvp_kernels_require_lowering": %s,\n' "$(count_matches "semantic_raw_kernel_requires_lowering" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_fwddiff_raw_jvp_kernels": %s,\n' "$(count_matches "enzyme_fwddiff_raw_buffer_calls" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_raw_jvp_fwddiff_calls": %s,\n' "$(count_matches "ida_raw_jvp_fwddiff" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_context_input_calls": %s,\n' "$(count_matches "ida_raw_jvp_context_input" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_raw_context_input_indices_attrs": %s,\n' "$(count_matches "enzymexla.sundials.context_input_indices" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_raw_non_model_context_input_indices_attrs": %s,\n' "$(count_matches "enzymexla.sundials.non_model_context_input_indices" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_raw_context_input_count_attrs": %s,\n' "$(count_matches "enzymexla.sundials.context_input_count" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_context_input_indices_attrs": %s,\n' "$(count_matches "enzymexla.sundials.runtime_context_input_indices" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_non_model_context_input_indices_attrs": %s,\n' "$(count_matches "enzymexla.sundials.runtime_non_model_context_input_indices" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_context_input_count_attrs": %s,\n' "$(count_matches "enzymexla.sundials.runtime_context_input_count" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_host_input_provider_attrs": %s,\n' "$(count_matches "enzymexla.sundials.runtime_host_input_provider" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_host_input_provider_functions": %s,\n' "$(count_regex "llvm\\.func @__enzymexla_sundials_ida_fill_generated_jvp_inputs" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_host_input_provider_plan_attrs": %s,\n' "$(count_matches "input_provider = @__enzymexla_sundials_ida_fill_generated_jvp_inputs" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_host_input_provider_resolve_calls": %s,\n' "$(count_matches "ida_jvp_context_non_model_input_resolve" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_accumulate_raw_jvp_calls": %s,\n' "$(count_matches "ida_raw_jvp_accumulate" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_context_input_declarations": %s,\n' "$(count_regex "llvm\\.func @__enzymexla_sundials_ida_context_input" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_host_input_resolver_declarations": %s,\n' "$(count_regex "llvm\\.func @__enzymexla_sundials_ida_resolve_generated_jvp_input" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_llvm_only_enzymexla_metadata": %s,\n' "$(count_matches "enzymexla." "${bridge_runtime_llvm_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_llvm_only_gridkit_metadata": %s,\n' "$(count_matches "gridkit." "${bridge_runtime_llvm_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_object_generated_symbols": %s,\n' "$(count_regex "__enzymexla_sundials_ida_(fill_generated_jvp_inputs|setup_generated_jactimes|teardown_generated_jactimes|jactimes_|jvp_kernel_|raw_jvp_kernel_|register_jactimes_|setup_jactimes_|teardown_jactimes_)" "${bridge_runtime_symbols}")" >> "${summary}"
printf '    "semantic_bridge_runtime_object_input_provider_symbols": %s,\n' "$(count_matches "__enzymexla_sundials_ida_fill_generated_jvp_inputs" "${bridge_runtime_symbols}")" >> "${summary}"
printf '    "semantic_bridge_runtime_object_setup_dispatcher_symbols": %s,\n' "$(count_matches "__enzymexla_sundials_ida_setup_generated_jactimes" "${bridge_runtime_symbols}")" >> "${summary}"
printf '    "semantic_bridge_runtime_object_teardown_dispatcher_symbols": %s,\n' "$(count_matches "__enzymexla_sundials_ida_teardown_generated_jactimes" "${bridge_runtime_symbols}")" >> "${summary}"
printf '    "semantic_bridge_runtime_object_jactimes_symbols": %s,\n' "$(count_matches "__enzymexla_sundials_ida_jactimes_" "${bridge_runtime_symbols}")" >> "${summary}"
printf '    "semantic_bridge_runtime_object_raw_jvp_symbols": %s,\n' "$(count_matches "__enzymexla_sundials_ida_raw_jvp_kernel_" "${bridge_runtime_symbols}")" >> "${summary}"
printf '    "semantic_bridge_runtime_smoke_success_lines": %s,\n' "$(count_matches "generated runtime glue smoke: ok" "${bridge_runtime_smoke_log}")" >> "${summary}"
printf '    "gridkit_runtime_evaluator_generated_jvp_input_hooks": %s,\n' "$(count_matches "generatedJvpInput" "${gridkit_root}/GridKit/Model/Evaluator.hpp")" >> "${summary}"
printf '    "gridkit_runtime_component_generated_jvp_input_hooks": %s,\n' "$(count_matches "generatedJvpInput" "${gridkit_root}/GridKit/Model/PhasorDynamics/Component.hpp")" >> "${summary}"
printf '    "gridkit_runtime_genclassical_generated_jvp_input_hooks": %s,\n' "$(count_matches "generatedJvpInput" "${gridkit_root}/GridKit/Model/PhasorDynamics/SynchronousMachine/GenClassical/GenClassical.hpp")" >> "${summary}"
printf '    "gridkit_runtime_ida_typed_input_resolver_collect_calls": %s,\n' "$(count_matches "resolveGeneratedJvpInputFromModel" "${gridkit_root}/GridKit/Solver/Dynamic/Ida.cpp")" >> "${summary}"
printf '    "gridkit_runtime_scoped_input_resolver_registry": %s,\n' "$(count_matches "ScopedGeneratedIdaJvpInputResolver" "${gridkit_root}/GridKit/Solver/Dynamic/IdaJvpRuntime.cpp")" >> "${summary}"
printf '    "semantic_bridge_runtime_accumulate_raw_jvp_declarations": %s,\n' "$(count_regex "llvm\\.func @__enzymexla_sundials_ida_accumulate_raw_jvp" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_context_registration_calls": %s,\n' "$(count_matches "enzymexla.sundials.role = \"ida_jvp_context_registration\"" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_context_registration_helper_calls": %s,\n' "$(count_matches "ida_jvp_context_registration_helper" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_context_registration_declarations": %s,\n' "$(count_regex "llvm\\.func @__enzymexla_sundials_ida_register_jvp_context" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_context_create_calls": %s,\n' "$(count_matches "ida_jvp_context_create" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_context_remember_calls": %s,\n' "$(count_matches "ida_jvp_context_remember" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_context_destroy_calls": %s,\n' "$(count_matches "ida_jvp_context_destroy" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_context_destroy_for_ida_mem_calls": %s,\n' "$(count_matches "ida_jvp_context_destroy_for_ida_mem" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_linear_solver_remember_calls": %s,\n' "$(count_matches "ida_iterative_linear_solver_remember" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_linear_solver_destroy_for_ida_mem_calls": %s,\n' "$(count_matches "ida_iterative_linear_solver_destroy_for_ida_mem" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_context_output_size_calls": %s,\n' "$(count_matches "ida_jvp_context_output_size" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_context_create_declarations": %s,\n' "$(count_regex "llvm\\.func @__enzymexla_sundials_ida_create_jvp_context" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_context_destroy_declarations": %s,\n' "$(count_regex "llvm\\.func @__enzymexla_sundials_ida_destroy_jvp_context" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_context_remember_declarations": %s,\n' "$(count_regex "llvm\\.func @__enzymexla_sundials_ida_remember_jvp_context" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_context_destroy_remembered_declarations": %s,\n' "$(count_regex "llvm\\.func @__enzymexla_sundials_ida_destroy_remembered_jvp_context" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_linear_solver_remember_declarations": %s,\n' "$(count_regex "llvm\\.func @__enzymexla_sundials_ida_remember_linear_solver" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_linear_solver_destroy_remembered_declarations": %s,\n' "$(count_regex "llvm\\.func @__enzymexla_sundials_ida_destroy_remembered_linear_solver" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_raw_jvp_kernel_attrs": %s,\n' "$(count_matches "enzymexla.sundials.runtime_raw_jvp_kernel" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_context_setup_attrs": %s,\n' "$(count_matches "enzymexla.sundials.runtime_context_setup" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_context_teardown_attrs": %s,\n' "$(count_matches "enzymexla.sundials.runtime_context_teardown" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_lowered_raw_jvp_kernel_attrs": %s,\n' "$(count_matches "enzymexla.sundials.lowered_raw_jvp_kernel" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_nvector_data_access_calls": %s,\n' "$(count_regex "llvm\\.call @N_VGetArrayPointer" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_nvector_length_calls": %s,\n' "$(count_regex "llvm\\.call @N_VGetLength" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_yp_tangent_scale_calls": %s,\n' "$(count_regex "llvm\\.call @N_VScale" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_yp_tangent_scale_roles": %s,\n' "$(count_matches "ida_yp_tangent_scale" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_nvector_scale_declarations": %s,\n' "$(count_regex "llvm\\.func @N_VScale" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_nvector_length_declarations": %s,\n' "$(count_regex "llvm\\.func @N_VGetLength" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_user_data_registration_calls": %s,\n' "$(count_regex "llvm\\.call @IDASetUserData" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_user_data_registration_roles": %s,\n' "$(count_matches "ida_user_data_registration" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_user_data_declarations": %s,\n' "$(count_regex "llvm\\.func @IDASetUserData" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_runtime_callback_context_attrs": %s,\n' "$(count_matches "enzymexla.sundials.callback_context" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_ida_set_jac_times_calls": %s,\n' "$(count_regex "llvm\\.call @IDASetJacTimes" "${bridge_runtime_mlir}")" >> "${summary}"
printf '    "semantic_bridge_iterative_solver_calls": %s\n' "$(count_regex "llvm\\.call @SUNLinSol_SPGMR" "${bridge_runtime_mlir}")" >> "${summary}"
printf '  },\n' >> "${summary}"
printf '  "sha256": {\n' >> "${summary}"
printf '    "imported_mlir": %s,\n' "$(json_string "$(file_sha256 "${imported_mlir}")")" >> "${summary}"
printf '    "printed_mlir": %s,\n' "$(json_string "$(file_sha256 "${printed_mlir}")")" >> "${summary}"
printf '    "marked_mlir": %s,\n' "$(json_string "$(file_sha256 "${marked_mlir}")")" >> "${summary}"
printf '    "object": %s,\n' "$(json_string "$(file_sha256 "${object_file}")")" >> "${summary}"
printf '    "ida_host_imported_mlir": %s,\n' "$(json_string "$(file_sha256 "${ida_imported_mlir}")")" >> "${summary}"
printf '    "ida_host_printed_mlir": %s,\n' "$(json_string "$(file_sha256 "${ida_printed_mlir}")")" >> "${summary}"
printf '    "ida_host_marked_mlir": %s,\n' "$(json_string "$(file_sha256 "${ida_marked_mlir}")")" >> "${summary}"
printf '    "ida_host_object": %s,\n' "$(json_string "$(file_sha256 "${ida_object_file}")")" >> "${summary}"
printf '    "semantic_bridge_input_mlir": %s,\n' "$(json_string "$(file_sha256 "${bridge_mlir}")")" >> "${summary}"
printf '    "semantic_bridge_selected_mlir": %s,\n' "$(json_string "$(file_sha256 "${bridge_selected_mlir}")")" >> "${summary}"
printf '    "semantic_bridge_runtime_mlir": %s,\n' "$(json_string "$(file_sha256 "${bridge_runtime_mlir}")")" >> "${summary}"
printf '    "semantic_bridge_runtime_llvm_mlir": %s,\n' "$(json_string "$(file_sha256 "${bridge_runtime_llvm_mlir}")")" >> "${summary}"
printf '    "semantic_bridge_runtime_llvm_ir": %s,\n' "$(json_string "$(file_sha256 "${bridge_runtime_llvm_ir}")")" >> "${summary}"
printf '    "semantic_bridge_runtime_object": %s,\n' "$(json_string "$(file_sha256 "${bridge_runtime_object}")")" >> "${summary}"
printf '    "semantic_bridge_runtime_smoke_executable": %s\n' "$(json_string "$(file_sha256 "${bridge_runtime_smoke_exe}")")" >> "${summary}"
printf '  }\n' >> "${summary}"
printf '}\n' >> "${summary}"

echo "wrote ${imported_mlir}"
echo "wrote ${printed_mlir}"
if [[ -f "${marked_mlir}" ]]; then
  echo "wrote ${marked_mlir}"
fi
echo "wrote ${object_file}"
if [[ -f "${ida_imported_mlir}" ]]; then
  echo "wrote ${ida_imported_mlir}"
fi
if [[ -f "${ida_printed_mlir}" ]]; then
  echo "wrote ${ida_printed_mlir}"
fi
if [[ -f "${ida_marked_mlir}" ]]; then
  echo "wrote ${ida_marked_mlir}"
fi
if [[ -f "${ida_object_file}" ]]; then
  echo "wrote ${ida_object_file}"
fi
if [[ -f "${bridge_mlir}" ]]; then
  echo "wrote ${bridge_mlir}"
fi
if [[ -f "${bridge_selected_mlir}" ]]; then
  echo "wrote ${bridge_selected_mlir}"
fi
if [[ -f "${bridge_runtime_mlir}" ]]; then
  echo "wrote ${bridge_runtime_mlir}"
fi
if [[ -f "${bridge_runtime_llvm_mlir}" ]]; then
  echo "wrote ${bridge_runtime_llvm_mlir}"
fi
if [[ -f "${bridge_runtime_llvm_ir}" ]]; then
  echo "wrote ${bridge_runtime_llvm_ir}"
fi
if [[ -f "${bridge_runtime_object}" ]]; then
  echo "wrote ${bridge_runtime_object}"
fi
if [[ -f "${bridge_runtime_symbols}" ]]; then
  echo "wrote ${bridge_runtime_symbols}"
fi
if [[ -f "${bridge_runtime_smoke_exe}" ]]; then
  echo "wrote ${bridge_runtime_smoke_exe}"
fi
if [[ -f "${bridge_runtime_smoke_log}" ]]; then
  echo "wrote ${bridge_runtime_smoke_log}"
fi
echo "wrote ${summary}"

if [[ "${roundtrip_status}" -ne 0 ]]; then
  echo "Reactant import round-trip failed; see ${roundtrip_log}" >&2
  exit "${roundtrip_status}"
fi

if [[ -n "${marker_status}" && "${marker_status}" -ne 0 ]]; then
  echo "GridKit sparse Jacobian marker failed; see ${marker_log}" >&2
  exit "${marker_status}"
fi

if [[ "${ida_attempted}" == "true" && -n "${ida_roundtrip_status}" &&
      "${ida_roundtrip_status}" -ne 0 ]]; then
  echo "GridKit IDA host Reactant import round-trip failed; see ${ida_roundtrip_log}" >&2
  exit "${ida_roundtrip_status}"
fi

if [[ -n "${ida_marker_status}" && "${ida_marker_status}" -ne 0 ]]; then
  echo "GridKit IDA host SUNDIALS recovery failed; see ${ida_marker_log}" >&2
  exit "${ida_marker_status}"
fi

if [[ -n "${bridge_status}" && "${bridge_status}" -ne 0 ]]; then
  echo "GridKit semantic bridge matrix-free selection failed; see ${bridge_log}" >&2
  exit "${bridge_status}"
fi

if [[ -n "${bridge_runtime_status}" && "${bridge_runtime_status}" -ne 0 ]]; then
  echo "GridKit semantic bridge runtime glue lowering failed; see ${bridge_runtime_log}" >&2
  exit "${bridge_runtime_status}"
fi

if [[ -n "${bridge_runtime_strip_status}" && "${bridge_runtime_strip_status}" -ne 0 ]]; then
  echo "GridKit semantic bridge runtime glue metadata strip failed; see ${bridge_runtime_strip_log}" >&2
  exit "${bridge_runtime_strip_status}"
fi

if [[ -n "${bridge_runtime_translate_status}" && "${bridge_runtime_translate_status}" -ne 0 ]]; then
  echo "GridKit semantic bridge runtime glue LLVM translation failed; see ${bridge_runtime_translate_log}" >&2
  exit "${bridge_runtime_translate_status}"
fi

if [[ -n "${bridge_runtime_object_status}" && "${bridge_runtime_object_status}" -ne 0 ]]; then
  echo "GridKit semantic bridge runtime glue object generation failed; see ${bridge_runtime_object_log}" >&2
  exit "${bridge_runtime_object_status}"
fi

if [[ -n "${bridge_runtime_symbols_status}" && "${bridge_runtime_symbols_status}" -ne 0 ]]; then
  echo "GridKit semantic bridge runtime glue symbol extraction failed; see ${bridge_runtime_object_log}" >&2
  exit "${bridge_runtime_symbols_status}"
fi

if [[ -n "${bridge_runtime_smoke_compile_status}" &&
      "${bridge_runtime_smoke_compile_status}" -ne 0 ]]; then
  echo "GridKit semantic bridge runtime glue smoke compile failed; see ${bridge_runtime_smoke_log}" >&2
  exit "${bridge_runtime_smoke_compile_status}"
fi

if [[ -n "${bridge_runtime_smoke_run_status}" &&
      "${bridge_runtime_smoke_run_status}" -ne 0 ]]; then
  echo "GridKit semantic bridge runtime glue smoke run failed; see ${bridge_runtime_smoke_log}" >&2
  exit "${bridge_runtime_smoke_run_status}"
fi

if [[ -n "${default_status}" && "${default_status}" -ne 0 ]]; then
  echo "Default Reactant pipeline failed with exit ${default_status}; see ${default_log}" >&2
fi
