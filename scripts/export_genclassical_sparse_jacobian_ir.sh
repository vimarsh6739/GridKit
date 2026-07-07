#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
gridkit_root="$(cd "${script_dir}/.." && pwd)"
out_dir="${1:-${gridkit_root}/build/reactant-jacobian-export}"
src="${gridkit_root}/examples/Experimental/ReactantJacobianRaise/GenClassicalSparseJacobianHarness.cpp"
out="${out_dir}/genclassical_sparse_jacobian.ll"
summary="${out_dir}/genclassical_sparse_jacobian_export.json"

mkdir -p "${out_dir}"

cxx="${CXX:-clang++}"

"${cxx}" \
  -std=c++20 \
  -O0 \
  -g0 \
  -S \
  -emit-llvm \
  -fno-discard-value-names \
  -DGRIDKIT_ENABLE_ENZYME \
  -I"${gridkit_root}" \
  -I"${gridkit_root}/third-party/magic-enum/include" \
  "${src}" \
  -o "${out}"

echo "wrote ${out}"

fwddiff_lines="$(grep -c "__enzyme_fwddiff" "${out}" || true)"
todense_lines="$(grep -c "__enzyme_todense" "${out}" || true)"
sparse_store_lines="$(grep -c "sparse_store" "${out}" || true)"
entry_lines="$(grep -c "gridkit_genclassical_existing_sparse_jacobian" "${out}" || true)"

printf '{\n' > "${summary}"
printf '  "llvm_ir": "%s",\n' "${out}" >> "${summary}"
printf '  "matching_lines": {\n' >> "${summary}"
printf '    "__enzyme_fwddiff": %s,\n' "${fwddiff_lines}" >> "${summary}"
printf '    "__enzyme_todense": %s,\n' "${todense_lines}" >> "${summary}"
printf '    "sparse_store": %s,\n' "${sparse_store_lines}" >> "${summary}"
printf '    "gridkit_genclassical_existing_sparse_jacobian": %s\n' "${entry_lines}" >> "${summary}"
printf '  }\n' >> "${summary}"
printf '}\n' >> "${summary}"

echo "wrote ${summary}"

if command -v rg >/dev/null 2>&1; then
  rg -n "__enzyme_fwddiff|__enzyme_todense|sparse_store|gridkit_genclassical_existing_sparse_jacobian" "${out}" || true
fi
