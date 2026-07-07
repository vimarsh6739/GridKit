# Reactant Jacobian-to-JVP Compiler Path

This note records the concrete compiler boundary for raising GridKit's current
Enzyme sparse Jacobian path into Reactant/MLIR. It is not a replacement for the
implementation; it is the working map for the implementation.

## Boundary

```text
GridKit C++ source
  GenClassical::evaluateJacobian()
    DfDy/DfDyp/DfDwb/DhDy sparse helpers
      one-hot seed loop
      __enzyme_todense sparse output wrappers
      __enzyme_fwddiff(ModelWrapper<..., residual>::eval, activity metadata)
        evaluateInternalResidual / evaluateBusResidual
          y, yp, wb -> residual

LLVM IR export without running the Enzyme pass
  __enzyme_fwddiff calls remain visible
  sparse output callbacks remain visible
  existing Jacobian source remains unchanged

Reactant LLVM pass
  serializes LLVM module
  calls Enzyme-JAX runLLVMToMLIRRoundTrip(...)
  imported LLVM dialect MLIR can be dumped before the default raising pipeline
  a controlled override pipeline can round-trip that import back to an object

MLIR compiler work
  recover Jacobian semantics from the repeated one-hot fwddiff/sparse-store pattern
  represent IDA linear-solver semantics with a semantic op, separately from raw SUNDIALS ABI calls
  rewrite legal Jacobian actions to a single JVP callback
  lower solver semantics back to host runtime glue and SUNDIALS JacTimes setup
```

The first interception point is the LLVM module handed to Reactant before
Enzyme sparse lowering runs. This avoids the current sparse-lowering crash while
preserving the source-level Jacobian expression.

The second, currently implemented, interception point is the imported LLVM
dialect module inside Enzyme-JAX. That module still contains the sparse helper
functions, the `__enzyme_todense` wrappers, the `sparse_store` callback
addresses, and the `__enzyme_fwddiff` residual calls.

## Current Export Harness

The export-only harness lives at:

```text
examples/Experimental/ReactantJacobianRaise/GenClassicalSparseJacobianHarness.cpp
```

It includes the existing `BusEnzyme.cpp` and `GenClassicalEnzyme.cpp`
translation units, constructs a tiny bus plus classical generator, and calls
the existing `evaluateJacobian()` methods. It does not call the matrix-free JVP
prototype and does not define a new GridKit runtime API.

Export LLVM IR with:

```bash
bash GridKit/scripts/export_genclassical_sparse_jacobian_ir.sh
```

The expected output is:

```text
GridKit/build/reactant-jacobian-export/genclassical_sparse_jacobian.ll
GridKit/build/reactant-jacobian-export/genclassical_sparse_jacobian_export.json
```

The exported LLVM IR should contain:

```text
gridkit_genclassical_existing_sparse_jacobian
__enzyme_fwddiff
__enzyme_todense
sparse_store
```

## Reactant Import and Marker Export

Build the Reactant clang wrapper from the Reactant checkout:

```bash
(cd Reactant/enzyme && \
  bazel build --repo_env=CC=clang-18 \
    --copt=-fbracket-depth=1024 \
    --host_copt=-fbracket-depth=1024 \
    -c dbg //:gen_reactant-clang++ //:reactant-clang)
```

Then export the imported Reactant MLIR, run the GridKit sparse-Jacobian marker
pass when `Enzyme-JAX/bazel-bin/enzymexlamlir-opt` is available, and write a
machine-readable summary:

```bash
bash GridKit/scripts/export_genclassical_reactant_import_mlir.sh
```

The script uses `OVERRIDE_PASS_PIPELINE=print{...}` so Reactant imports the
module, prints the LLVM dialect MLIR, and round-trips it back to an object
without running the crashing default raise pipeline. The expected artifacts are:

```text
GridKit/build/reactant-jacobian-export/reactant/genclassical_reactant_imported.mlir
GridKit/build/reactant-jacobian-export/reactant/genclassical_reactant_roundtrip_input.mlir
GridKit/build/reactant-jacobian-export/reactant/genclassical_reactant_marked_sparse_jacobian.mlir
GridKit/build/reactant-jacobian-export/reactant/genclassical_reactant_roundtrip.o
GridKit/build/reactant-jacobian-export/reactant/gridkit_ida_host_reactant_imported.mlir
GridKit/build/reactant-jacobian-export/reactant/gridkit_ida_host_reactant_roundtrip_input.mlir
GridKit/build/reactant-jacobian-export/reactant/gridkit_ida_host_recovered_sundials.mlir
GridKit/build/reactant-jacobian-export/reactant/gridkit_ida_host_reactant_roundtrip.o
GridKit/build/reactant-jacobian-export/reactant/gridkit_semantic_bridge_matrix_free_input.mlir
GridKit/build/reactant-jacobian-export/reactant/gridkit_semantic_bridge_matrix_free_selected.mlir
GridKit/build/reactant-jacobian-export/reactant/gridkit_semantic_bridge_runtime_glue.mlir
GridKit/build/reactant-jacobian-export/reactant/genclassical_reactant_import_export.json
```

With `GRIDKIT_REACTANT_TRY_DEFAULT=1`, the same script also probes the default
Reactant pipeline and records its exit status and log in the JSON summary. The
same export also raises a declaration-only IDA host harness that includes
GridKit's existing `Ida.cpp` configuration path. The SUNDIALS shim headers used
there are compile/import declarations only; SUNDIALS remains an external runtime
boundary and no SUNDIALS implementation is imported. The current full GridKit
harness status is:

```text
roundtrip.exit_code = 0
marker.exit_code = 0
ida_host.roundtrip_exit_code = 0
ida_host.marker_exit_code = 0
semantic_bridge.runtime_exit_code = 0
default_pipeline.exit_code = 139
marked_attributes.semantic_jacobian_materializations = 8
marked_attributes.semantic_jacobian_materializations_with_residual = 8
marked_attributes.semantic_jacobian_materializations_with_activity = 8
marked_attributes.semantic_jacobian_materializations_with_structured_activity = 8
marked_attributes.semantic_jacobian_materializations_with_active_input = 8
marked_attributes.semantic_jacobian_materializations_with_dimension_args = 8
marked_attributes.semantic_jacobian_materializations_with_sparse_layout = 8
marked_attributes.semantic_jacobian_materializations_with_sparse_buffers = 8
marked_attributes.semantic_jacobian_actions = 8
marked_attributes.semantic_jacobian_actions_with_materialization = 8
marked_attributes.semantic_jacobian_actions_with_sparse_layout = 8
marked_attributes.semantic_jacobian_actions_synthesized_attr = 1
marked_attributes.sundials_ida_matrix_free_selected_attr = 0
marked_attributes.semantic_sundials_ida_solves = 0
marked_attributes.semantic_sundials_ida_solves_recovered_attr = 0
marked_attributes.semantic_sundials_ida_explicit_matrix_solves = 0
marked_attributes.semantic_sundials_ida_jacobian_action_solves = 0
marked_attributes.sundials_ida_solves_linked_jacobian_actions_attr = 0
marked_attributes.ida_host_semantic_sundials_ida_solves = 3
marked_attributes.ida_host_semantic_sundials_ida_explicit_matrix_solves = 3
marked_attributes.ida_host_semantic_sundials_ida_jacobian_action_solves = 0
marked_attributes.ida_host_matrix_free_selected_attr = 0
marked_attributes.ida_host_recovered_attr = 1
marked_attributes.ida_host_user_data_registered_attrs = 3
marked_attributes.ida_host_user_data_registration_roles = 3
marked_attributes.ida_host_user_data_unwrap_calls = 16
marked_attributes.ida_host_sparse_direct_roles = 3
marked_attributes.ida_host_jacobian_registration_roles = 3
marked_attributes.ida_host_linear_solver_source_function_attrs = 3
marked_attributes.ida_host_jacobian_registration_source_function_attrs = 3
marked_attributes.ida_host_jvp_setup_yy_template_operand_attrs = 12
marked_attributes.ida_host_jvp_setup_sunctx_operand_attrs = 12
marked_attributes.ida_host_jvp_setup_ida_mem_operand_attrs = 6
marked_attributes.ida_host_jvp_setup_model_operand_attrs = 3
marked_attributes.semantic_bridge_ida_solves = 1
marked_attributes.semantic_bridge_jacobian_action_solves = 1
marked_attributes.semantic_bridge_matrix_free_selected_attr = 1
marked_attributes.semantic_bridge_allow_matrix_free_attrs = 1
marked_attributes.semantic_bridge_host_linear_solver_source_attrs = 1
marked_attributes.semantic_bridge_host_jacobian_registration_source_attrs = 1
marked_attributes.semantic_bridge_effective_jacobian_actions_synthesized_attr = 1
marked_attributes.semantic_bridge_effective_jacobian_actions = 1
marked_attributes.semantic_bridge_runtime_glue_emitted_attr = 1
marked_attributes.semantic_bridge_runtime_jvp_kernel_adapters_emitted_attr = 1
marked_attributes.semantic_bridge_runtime_raw_jvp_kernels_emitted_attr = 1
marked_attributes.semantic_bridge_runtime_lowered_raw_jvp_kernels_linked_attr = 0
marked_attributes.semantic_bridge_runtime_jactimes_callbacks = 1
marked_attributes.semantic_bridge_runtime_registrations = 1
marked_attributes.semantic_bridge_runtime_context_setup_functions = 1
marked_attributes.semantic_bridge_runtime_context_teardown_functions = 1
marked_attributes.semantic_bridge_runtime_host_linear_solver_source_attrs = 5
marked_attributes.semantic_bridge_runtime_host_jacobian_registration_source_attrs = 5
marked_attributes.semantic_bridge_runtime_host_configure_source_attrs = 4
marked_attributes.semantic_bridge_runtime_placeholder_callbacks = 0
marked_attributes.semantic_bridge_runtime_delegating_callbacks = 1
marked_attributes.semantic_bridge_runtime_jvp_kernel_adapters = 1
marked_attributes.semantic_bridge_runtime_jvp_kernel_adapters_unpack_nvector = 1
marked_attributes.semantic_bridge_runtime_jvp_kernels_require_lowering = 0
marked_attributes.semantic_bridge_runtime_jvp_kernel_attrs = 1
marked_attributes.semantic_bridge_runtime_raw_jvp_kernels = 1
marked_attributes.semantic_bridge_runtime_raw_jvp_kernel_calls = 1
marked_attributes.semantic_bridge_runtime_raw_jvp_kernels_require_lowering = 0
marked_attributes.semantic_bridge_runtime_fwddiff_raw_jvp_kernels = 1
marked_attributes.semantic_bridge_runtime_raw_jvp_fwddiff_calls = 2
marked_attributes.semantic_bridge_runtime_context_input_calls = 4
marked_attributes.semantic_bridge_runtime_raw_context_input_indices_attrs = 1
marked_attributes.semantic_bridge_runtime_raw_non_model_context_input_indices_attrs = 1
marked_attributes.semantic_bridge_runtime_raw_context_input_count_attrs = 1
marked_attributes.semantic_bridge_runtime_context_input_indices_attrs = 3
marked_attributes.semantic_bridge_runtime_non_model_context_input_indices_attrs = 3
marked_attributes.semantic_bridge_runtime_context_input_count_attrs = 3
marked_attributes.semantic_bridge_runtime_accumulate_raw_jvp_calls = 1
marked_attributes.semantic_bridge_runtime_context_input_declarations = 1
marked_attributes.semantic_bridge_runtime_accumulate_raw_jvp_declarations = 1
marked_attributes.semantic_bridge_runtime_context_registration_calls = 1
marked_attributes.semantic_bridge_runtime_context_registration_helper_calls = 1
marked_attributes.semantic_bridge_runtime_context_registration_declarations = 1
marked_attributes.semantic_bridge_runtime_context_create_calls = 1
marked_attributes.semantic_bridge_runtime_context_destroy_calls = 1
marked_attributes.semantic_bridge_runtime_context_output_size_calls = 1
marked_attributes.semantic_bridge_runtime_context_create_declarations = 1
marked_attributes.semantic_bridge_runtime_context_destroy_declarations = 1
marked_attributes.semantic_bridge_runtime_raw_jvp_kernel_attrs = 1
marked_attributes.semantic_bridge_runtime_context_setup_attrs = 1
marked_attributes.semantic_bridge_runtime_context_teardown_attrs = 1
marked_attributes.semantic_bridge_runtime_lowered_raw_jvp_kernel_attrs = 0
marked_attributes.semantic_bridge_runtime_nvector_data_access_calls = 7
marked_attributes.semantic_bridge_runtime_nvector_length_calls = 1
marked_attributes.semantic_bridge_runtime_yp_tangent_scale_calls = 1
marked_attributes.semantic_bridge_runtime_yp_tangent_scale_roles = 1
marked_attributes.semantic_bridge_runtime_nvector_scale_declarations = 1
marked_attributes.semantic_bridge_runtime_nvector_length_declarations = 1
marked_attributes.semantic_bridge_runtime_user_data_registration_calls = 1
marked_attributes.semantic_bridge_runtime_user_data_registration_roles = 1
marked_attributes.semantic_bridge_runtime_user_data_declarations = 1
marked_attributes.semantic_bridge_runtime_callback_context_attrs = 2
marked_attributes.semantic_bridge_ida_set_jac_times_calls = 1
marked_attributes.semantic_bridge_iterative_solver_calls = 1
```

The marker and action-synthesis passes currently record:

```text
enzymexla.jacobian_materialization
  materializer = @sparse_helper
  residual = @residual_wrapper
  method = <one_hot_forward>
  storage = <sparse_callback>
  fwddiff_calls = ...
  todense_calls = ...
  sparse_store_callbacks = ...
  enzyme_activity = [...]
  input_activity = [...]
  output_activity = [...]
  active_input_index = ...
  active_output_index = ...
  output_dimension_arg = ...
  active_input_dimension_arg = ...
  seed_loop_dimension_arg = ...
  output_index_map_arg = ...
  active_input_index_map_arg = ...
  sparse_assembly = "coo_column_seeded_callback"
  sparse_rows_arg = ...
  sparse_cols_arg = ...
  sparse_values_arg = ...
  sparse_nnz_arg = ...
  input_count = ...
  output_count = ...

gridkit.jacobian.marked_sparse_helpers = 8
gridkit.jacobian.materialization = "enzyme_sparse_one_hot"
gridkit.jacobian.action = "residual_jvp_candidate"
gridkit.solver = "ida_jac_times"

enzymexla.jacobian_action @generated_action
  materialization = @sparse_helper
  residual = @residual_wrapper
  active_input_index = ...
  active_output_index = ...
  input_activity = [...]
  output_activity = [...]
  output_dimension_arg = ...
  active_input_dimension_arg = ...
  seed_loop_dimension_arg = ...
  sparse_assembly = "coo_column_seeded_callback"
  sparse_rows_arg = ...
  sparse_cols_arg = ...
  sparse_values_arg = ...
  sparse_nnz_arg = ...
```

Those eight helpers are the `DfDy`, `DfDyp`, `DfDwb`, and `DhDy` sparse
materialization helpers for both index-type instantiations emitted by the
harness. The `enzymexla.jacobian_materialization` op is the generic semantic
record; the `gridkit.*` attributes are retained as compatibility/debug
metadata on the recovered LLVM helper body and calls. The `residual` symbol is
recovered from the first `__enzyme_fwddiff` operand when it is an
`llvm.mlir.addressof` and all `__enzyme_fwddiff` calls in the helper agree.
The `enzyme_activity` array is the ordered sequence of loaded Enzyme ABI
activity markers, such as `enzyme_const`, `enzyme_dup`, and
`enzyme_dupnoneed`, recovered from each `__enzyme_fwddiff` call when the calls
agree. The `input_activity` and `output_activity` arrays are derived from that
ABI activity list when the residual wrapper has the same number of arguments,
returns no direct values, and the final activity marker is output-like. When
exactly one input activity marker is differentiated, `active_input_index`
records its residual-wrapper input index and `active_output_index` records the
single materialized output index.

For the currently recognized sparse-helper ABI, the marker also records the
dynamic dimensions and sparse COO callback layout generically in the semantic
record. `output_dimension_arg` points at the materializer's residual-count
argument, `active_input_dimension_arg` and `seed_loop_dimension_arg` point at
the independent-variable count used by the one-hot loop, and the index-map plus
COO buffer attributes point at the materializer arguments passed through the
sparse `__enzyme_todense` callback. The recovery identifies sparse output
buffers by collecting function pointer arguments from the `__enzyme_todense`
call that carries the sparse-store callback, so the extra `DfDyp` scale
parameter does not shift the recovered map and buffer slots.

`--synthesize-sundials-ida-jacobian-actions` then creates a generic
`enzymexla.jacobian_action` symbol for each complete materialization record.
This action record is not a hand-written GridKit JVP and it is not yet runtime
callback code. It is the compiler-visible bridge that says the recovered
materializer can be consumed as a JVP/action, preserving the residual symbol,
activity split, dynamic dimensions, and sparse callback layout needed by later
lowering. When an `enzymexla.sundials.ida_solve` op already requests
`jacobian_demand = <jacobian_action>` and names the explicit materializer as
its `jacobian`, the same pass fills in the generated `jacobian_action` symbol.
The sparse-Jacobian-only GridKit artifact does not instantiate the host IDA
configuration path, so those action records are synthesized but no real solve is
linked in that artifact yet. The separate IDA host artifact now recovers real
explicit-sparse/direct IDA solve records, but they are not yet linked to the
GenClassical Jacobian action records because the two source regions are still
exported separately. To make that boundary explicit and test the compiler
decision, the export script also generates
`gridkit_semantic_bridge_matrix_free_input.mlir`: a combined semantic overlay
that keeps the sparse materialization/action records, inserts an IDA solve
record with `enzymexla.sundials.allow_matrix_free`, and preserves the recovered
host `Ida::Residual`, `Ida::Jac`, `configureSimulation()`, and
`configureLinearSolverSparse()` symbols as provenance attributes. The recovered
linear-solver helper is carried through the bridge as
`bridge_host_linear_solver_source_function` and
`bridge_host_jacobian_registration_source_function`, so the generated runtime
glue names the concrete host helper that still owns the original KLU/Jacobian
registration sequence. Running synthesis plus
`--select-sundials-ida-matrix-free` on this overlay now makes the compiler pair
the recovered `DfDy` and `DfDyp` materializers into a semantic IDA effective
Jacobian action and produces
`gridkit_semantic_bridge_matrix_free_selected.mlir`, where the bridged solve is
retargeted to `linear_solver = <jacobian_action_iterative>` and
`jacobian_demand = <jacobian_action>`. This is compiler-visible selection
evidence. The follow-on `--emit-sundials-ida-runtime-glue-llvm` pass consumes
that selected solve and emits
`gridkit_semantic_bridge_runtime_glue.mlir`: an LLVM-dialect JacTimes callback
symbol, SUNDIALS declarations, and a registration helper that constructs
`SUNLinSol_SPGMR`, registers the generated JVP context with
`__enzymexla_sundials_ida_register_jvp_context`, calls `IDASetUserData`, calls
`IDASetLinearSolver`, and registers the callback with `IDASetJacTimes`. The
same pass now also emits a host-facing context setup helper that calls
`N_VGetLength(yy)` to derive the residual output size, marks that call with
`enzymexla.sundials.role = "ida_jvp_context_output_size"`, calls
`__enzymexla_sundials_ida_create_jvp_context`, stores the resulting context
pointer through an out parameter, and delegates to the generated registration
helper, plus a teardown helper that calls
`__enzymexla_sundials_ida_destroy_jvp_context`. The setup, registration,
teardown, and JacTimes callback helpers now carry
`enzymexla.sundials.host_linear_solver_source_function` and
`enzymexla.sundials.host_jacobian_registration_source_function` attributes
derived from the recovered host region; for the current GridKit artifact both
point at the `Ida<double, long>::configureLinearSolverSparse()` instantiation.
The registration helper is
marked with
`enzymexla.sundials.callback_context = "ida_jvp_user_data_context"`, making the
fourth helper argument an explicit reusable `IdaJvpUserData` context pointer
rather than an untyped model pointer. The generated callback currently carries
the selected Jacobian-action provenance.
When the selected `jacobian_action` already names an LLVM function with the IDA
JacTimes callback ABI, the generated callback delegates to that lowered JVP
kernel and returns its status. When the selected action is still a semantic
`enzymexla.jacobian_action` record, the pass now
synthesizes a JacTimes-ABI adapter function and has the callback delegate to
that adapter. The callback and adapter use the current IDA JacTimes vector ABI:
`tt, yy, yp, rr, v, Jv, cj, user_data, tmp1, tmp2`. The adapter is marked
`enzymexla.sundials.jvp_kernel_body = "nvector_unpack_and_raw_jvp_call"` and
`enzymexla.sundials.yp_tangent = "tmp1 = cj * v"`. It calls
`N_VScale(cj, v, tmp1)` to construct the IDA `yp` tangent, calls
`N_VGetArrayPointer` on `yy`, `yp`, `rr`, `v`, `Jv`, `tmp1`, and `tmp2`, and
then calls a raw-buffer JVP kernel. The raw kernel therefore receives
`tmp1Data` as the `yp` tangent buffer for
`dF/dy * v + dF/dyp * (cj * v)`. If the semantic action or solve already
names a compiler-lowered raw-buffer kernel through
`enzymexla.sundials.lowered_raw_jvp_kernel`, or exactly one LLVM function
advertises `enzymexla.sundials.runtime_role = "lowered_raw_jvp_kernel"` plus
matching `enzymexla.sundials.jacobian_action = @...` provenance, the adapter
links to that symbol directly and the module records
`enzymexla.sundials.ida_lowered_raw_jvp_kernels_linked`. Otherwise, when the
semantic action has enough materializer metadata and the recovered `DfDy` and
`DfDyp` materializers each contain a single supported Enzyme forward-mode call,
the pass emits a raw-buffer kernel marked
`enzymexla.sundials.jvp_kernel_body = "enzyme_fwddiff_raw_buffer_calls"`. That
kernel calls the recovered Enzyme `__enzyme_fwddiff` wrappers for `y` and `yp`,
passes the IDA vector `v` as the `y` tangent, passes `tmp1Data` as the
`yp = cj * v` tangent, and accumulates the two contributions through
`__enzymexla_sundials_ida_accumulate_raw_jvp`. Non-SUNDIALS residual inputs are
loaded through `__enzymexla_sundials_ida_context_input(user_data, index)`. The
generated raw kernel records `enzymexla.sundials.context_input_indices = [0, 3]`,
`enzymexla.sundials.non_model_context_input_indices = [3]`, and
`enzymexla.sundials.context_input_count = 4 : i64`; the solve plus generated
setup/registration helpers carry the matching `runtime_*` context-input
contract, so the later host splice no longer has to infer the residual input
array shape from callback body calls.
GridKit now provides a reusable `IdaJvpUserData` support layer with C ABI entry
points for creating, registering, destroying, and discovering generated callback
contexts, unwrapping the original model pointer for legacy residual/Jacobian
callbacks, accessing context inputs, and accumulating the y/yp JVP
contributions. Generated contexts copy the residual input pointer slots at
creation time, so a compiler-generated setup call can assemble a temporary
pointer array without leaving the later IDA callback with a dangling array
reference. The remaining executable gap is host splicing: lowered code still
has to use the recorded context-input contract to build the residual input
pointer array, call the generated context setup
helper from the host configuration path, keep the returned context pointer alive
for IDA, and call the generated teardown helper when the solver no longer needs
the callback. The setup helper now derives the output size from the IDA `yy`
template via `N_VGetLength`, so host splicing no longer has to supply that
operand. If those preconditions fail, the fallback raw kernel is still marked
`semantic_raw_kernel_requires_lowering` and returns a nonzero status. Multiple
provenance-matching raw kernels are rejected rather than chosen arbitrarily.

`--recover-sundials-ida-llvm` is the first generic host-side solver recovery
pass. It scans imported LLVM dialect host functions for SUNDIALS IDA
configuration calls such as `IDAInit`, `IDASetLinearSolver`, `IDASetJacFn`,
`IDASetJacTimes`, `IDASetPreconditioner`, and the SUN linear-solver creation
calls. From those calls it emits `enzymexla.sundials.ida_solve` records without
raising the SUNDIALS implementation. The recovered records distinguish
explicit sparse direct solves using KLU plus `IDASetJacFn`, dense direct solves
without a user Jacobian callback, and iterative solves using `IDASetJacTimes`.
The pass now annotates host calls with operand-index roles needed by a future
splice, including `jvp_setup_yy_template_operand`,
`jvp_setup_sunctx_operand`, `jvp_setup_ida_mem_operand`, and
`jvp_setup_model_operand`. It also records which source function provided the
residual registration, user-data registration, linear solver, and Jacobian or
JacTimes registration. For split host configurations this separates the
top-level `configureSimulation()` source from the helper that owns
`IDASetLinearSolver` and `IDASetJacFn`.
The recovery now also composes split host helpers generically: a source function
that registers `IDAInit` may call a helper that configures `SUNLinSol_KLU` and
`IDASetJacFn`, and the pass summarizes those helper facts into one semantic
solve record at the residual-registration boundary. The synthetic LLVM-dialect
lit test covers both same-function and split-helper recovery. The current IDA
host GridKit artifact recovers three `enzymexla.sundials.ida_solve` records,
one for each visible `Ida<double, IdxT>` instantiation.

## Semantic IDA Solve Operation

The first compiler-visible representation for the SUNDIALS side is:

```text
enzymexla.sundials.ida_solve
```

It intentionally models only the semantic boundary needed by the compiler and
leaves SUNDIALS itself as host runtime code. The op records:

```text
residual = @residual_symbol
optional jacobian = @explicit_jacobian_symbol
optional jacobian_action = @jactimes_symbol
optional preconditioner = @preconditioner_symbol
linear_solver = <explicit_sparse_direct | explicit_dense_direct | jacobian_action_iterative>
jacobian_demand = <none | explicit_matrix | jacobian_action>
```

This gives the Jacobian-to-JVP transform an explicit solver-side demand to
match against the semantic Jacobian producer. In particular, an IDA solve with:

```text
linear_solver = <jacobian_action_iterative>
jacobian_demand = <jacobian_action>
```

is the representation that can legally consume an action equivalent to:

```text
(dF/dy) * v + cj * (dF/dyp) * v
```

The current op is parse/print covered and can drive generated LLVM-dialect
JacTimes registration glue, including the N_Vector-to-raw-buffer adapter
boundary. It still needs the generated raw-buffer kernel body to call the
lowered JVP numerical kernel.

## Reactant/Enzyme-JAX Hooks

`Reactant/enzyme/Enzyme/Enzyme.cpp` registers the LLVM pass pipeline name
`reactant`. The pass serializes the LLVM module and calls
`runLLVMToMLIRRoundTrip(input, outfile, backend, device_libraries)`.

`Enzyme-JAX/src/enzyme_ad/jax/raise.cpp` imports LLVM IR to MLIR, runs the
raising pipeline, and writes an MLIR dump when both an outfile is provided and
`EXPORT_REACTANT` is set.

Existing Enzyme-JAX support already has an `enzyme.jacobian` lowering pass for
StableHLO `dot_general(jacobian, vector)` patterns. GridKit needs a related but
more solver-specific path: the legality condition comes from IDA using an
iterative linear solver with `IDASetJacTimes`, not from a tensor dot alone.

The implemented solver-gated compiler hooks are:

```text
Enzyme-JAX/src/enzyme_ad/jax/Passes/LowerEnzymeJacobian.cpp
  --recover-sundials-ida-llvm
  --mark-gridkit-sparse-jacobian-llvm
  --synthesize-sundials-ida-jacobian-actions
  --select-sundials-ida-matrix-free
  --lower-gridkit-ida-jacobian-action-stablehlo
  --lower-sundials-ida-jacobian-action-stablehlo
```

`--recover-sundials-ida-llvm` recognizes SUNDIALS IDA host configuration calls
after LLVM import and emits semantic `enzymexla.sundials.ida_solve` records.
This makes the solver-side derivative demand visible without importing the
SUNDIALS implementation itself. It also annotates the matched LLVM calls with
debug roles such as `ida_residual_registration`, `ida_jacobian_registration`,
`ida_sparse_direct_linear_solver`, and `ida_jacobian_action_registration`.
The pass performs a small fixed-point summary over LLVM call edges so solver
configuration split across reusable host helpers is still recovered at the
function that locally registers the IDA residual.

`--mark-gridkit-sparse-jacobian-llvm` is the first recovery pass for the real
GridKit import. It marks LLVM dialect sparse helpers only when a helper has the
expected sparse-store callback address, `__enzyme_todense` wrappers, and an
`__enzyme_fwddiff` residual call. For each matched helper it now emits a
generic `enzymexla.jacobian_materialization` record that points at the
materializer function and records the one-hot forward-mode plus sparse-callback
evidence. It does not yet rewrite the helper body.

`--synthesize-sundials-ida-jacobian-actions` creates
`enzymexla.jacobian_action` symbols from complete
`enzymexla.jacobian_materialization` records and links eligible semantic IDA
solves to the generated action. This separates solver legality from the
low-level sparse helper body: the original explicit materializer remains
visible as the source computation, while the solver can now refer to the JVP
action that later lowering must turn into callback glue.

`--select-sundials-ida-matrix-free` is the first solver-selection pass. It
retargets an `enzymexla.sundials.ida_solve` from:

```text
linear_solver = <explicit_sparse_direct>
jacobian_demand = <explicit_matrix>
```

to:

```text
linear_solver = <jacobian_action_iterative>
jacobian_demand = <jacobian_action>
```

only when the solve has the explicit
`enzymexla.sundials.allow_matrix_free` opt-in attribute and a
`jacobian_action` can be resolved from its explicit materializer or an
unambiguous residual match. It annotates selected solves with
`enzymexla.sundials.matrix_free_selected` and records the module count in
`enzymexla.sundials.ida_matrix_free_selected`. This pass does not itself
rewrite numerical code; it changes the semantic solver demand that
`--emit-sundials-ida-runtime-glue-llvm` consumes when emitting generated
SUNDIALS callback registration glue.
The generated GridKit semantic bridge currently selects one such solve and
links it to the compiler-synthesized
`__enzymexla_sundials_ida_effective_jacobian_action_0`, which carries
`y_materialization = @DfDy`, `yp_materialization = @DfDyp`, and
`yp_active_input_index = 2` metadata for the IDA effective Jacobian
`dF/dy + cj * dF/dyp`. The module records
`enzymexla.sundials.ida_effective_jacobian_actions_synthesized = 1`.

`--emit-sundials-ida-runtime-glue-llvm` is the first runtime-lowering pass for
the selected semantic solve. For each `enzymexla.sundials.ida_solve` with
`linear_solver = <jacobian_action_iterative>`, `jacobian_demand =
<jacobian_action>`, and a resolved `jacobian_action`, it emits:

```text
llvm.func @__enzymexla_sundials_ida_jactimes_N(...)
llvm.func @__enzymexla_sundials_ida_jvp_kernel_N(...)
llvm.func @__enzymexla_sundials_ida_raw_jvp_kernel_N(...)
llvm.func @__enzymexla_sundials_ida_register_jactimes_N(
    %ida_mem, %yy, %sunctx, %user_data)
llvm.func @__enzymexla_sundials_ida_setup_jactimes_N(
    %ida_mem, %yy, %sunctx, %model, %inputs, %input_count,
    %context_out)
llvm.func @__enzymexla_sundials_ida_teardown_jactimes_N(%user_data)
llvm.func @SUNLinSol_SPGMR(...)
llvm.func @IDASetUserData(...)
llvm.func @IDASetLinearSolver(...)
llvm.func @IDASetJacTimes(...)
llvm.func @N_VGetArrayPointer(...)
llvm.func @N_VGetLength(...)
llvm.func @N_VScale(...)
llvm.func @__enzymexla_sundials_ida_register_jvp_context(...)
llvm.func @__enzymexla_sundials_ida_create_jvp_context(...)
llvm.func @__enzymexla_sundials_ida_destroy_jvp_context(...)
```

The solve is annotated with `enzymexla.sundials.runtime_jactimes_callback` and
`enzymexla.sundials.runtime_registration`. This is generated callback and
registration machinery. It is also annotated with
`enzymexla.sundials.runtime_context_setup` and
`enzymexla.sundials.runtime_context_teardown`, which name generated host-facing
lifecycle helpers for the `IdaJvpUserData` context. The registration helper is
marked
`enzymexla.sundials.callback_context = "ida_jvp_user_data_context"` and calls
`__enzymexla_sundials_ida_register_jvp_context` before `IDASetUserData`, so
IDA's `user_data` pointer is the generated JVP context recognized by the
runtime support library. If the selected action has already been lowered to an
LLVM function with the JacTimes ABI, the callback body calls it and is marked
`enzymexla.sundials.callback_body = "delegates_jvp_kernel"`. If the selected
action is still semantic, the pass generates
`__enzymexla_sundials_ida_jvp_kernel_N`, annotates the solve with
`enzymexla.sundials.runtime_jvp_kernel`, and delegates the callback to that
adapter. The adapter unpacks SUNDIALS `N_Vector` arguments with
`N_VScale(cj, v, tmp1)` followed by `N_VGetArrayPointer`, then calls the
raw-buffer kernel recorded on the solve through
`enzymexla.sundials.runtime_raw_jvp_kernel`. That raw kernel may be a
pre-existing compiler-lowered function named by
`enzymexla.sundials.lowered_raw_jvp_kernel`, or a unique LLVM function that
advertises `runtime_role = "lowered_raw_jvp_kernel"` and the same semantic
`jacobian_action` symbol. If no such symbol exists, the pass can now synthesize
`__enzymexla_sundials_ida_raw_jvp_kernel_N` directly from the recovered Enzyme
fwddiff materializer calls when the action metadata describes a single-output
IDA residual with `y` and optional `yp` active inputs. The generated raw kernel
uses `enzyme_fwddiff_raw_buffer_calls`, `ida_raw_jvp_context_input`, and
`ida_raw_jvp_accumulate` roles. GridKit's `IdaJvpRuntime` now defines the
corresponding C symbols:
`__enzymexla_sundials_ida_create_jvp_context`,
`__enzymexla_sundials_ida_destroy_jvp_context`,
`__enzymexla_sundials_ida_register_jvp_context`,
`__enzymexla_sundials_ida_unregister_jvp_context`,
`__enzymexla_sundials_ida_context_input`, and
`__enzymexla_sundials_ida_accumulate_raw_jvp`. Only unsupported layouts fall
back to `semantic_raw_kernel_requires_lowering`.

`--lower-gridkit-ida-jacobian-action-stablehlo` is the temporary
attribute-gated hook. It reuses the existing `enzyme.jacobian` action rewrite,
but only when the consuming
`stablehlo.dot_general` carries:

```text
gridkit.solver = "ida_jac_times"
```

`--lower-sundials-ida-jacobian-action-stablehlo` is the first semantic
solver-gated hook. It walks `enzymexla.sundials.ida_solve`, requires:

```text
linear_solver = <jacobian_action_iterative>
jacobian_demand = <jacobian_action>
```

and lowers only the referenced `jacobian_action` function. That makes
`enzymexla.sundials.ida_solve` the legality source instead of an out-of-band
dot attribute. The pass handles both the simple `dot_general(jacobian, vector)`
case and the IDA effective Jacobian action:

```text
(dF/dy) * v + (dF/dyp) * cjv
```

by rewriting it to a single `enzyme.fwddiff` of the residual with duplicate
activity for `y` and `yp`. For this semantic SUNDIALS path, successful action
lowering erases dead `enzyme.jacobian` materializations from the referenced
action function. If a requested action function still has a live Jacobian use
after the supported rewrites, for example because code inspects an arbitrary
matrix element, the pass fails instead of silently leaving a partially
materialized Jacobian path.

The lit coverage is:

```text
Enzyme-JAX/test/lit_tests/OptimizeAD/gridkit_sparse_jacobian_llvm_marker.mlir
Enzyme-JAX/test/lit_tests/OptimizeAD/gridkit_ida_jacobian_action.mlir
Enzyme-JAX/test/lit_tests/OptimizeAD/sundials_ida_llvm_recovery.mlir
Enzyme-JAX/test/lit_tests/OptimizeAD/sundials_ida_solve_semantic_op.mlir
Enzyme-JAX/test/lit_tests/OptimizeAD/sundials_ida_jacobian_action_synthesis.mlir
Enzyme-JAX/test/lit_tests/OptimizeAD/sundials_ida_effective_jacobian_action_synthesis.mlir
Enzyme-JAX/test/lit_tests/OptimizeAD/sundials_ida_matrix_free_selection.mlir
Enzyme-JAX/test/lit_tests/OptimizeAD/sundials_ida_matrix_free_prefers_effective_action.mlir
Enzyme-JAX/test/lit_tests/OptimizeAD/sundials_ida_runtime_glue_lowering.mlir
Enzyme-JAX/test/lit_tests/OptimizeAD/sundials_ida_runtime_glue_rejects_ambiguous_raw_kernel.mlir
Enzyme-JAX/test/lit_tests/OptimizeAD/sundials_ida_fwddiff_raw_jvp_kernel.mlir
Enzyme-JAX/test/lit_tests/OptimizeAD/sundials_ida_jacobian_action_lowering.mlir
Enzyme-JAX/test/lit_tests/OptimizeAD/sundials_ida_jacobian_action_rejects_unsupported_use.mlir
```

The LLVM marker test covers sparse-helper recognition. The SUNDIALS LLVM
recovery test covers host-call recovery for `IDASetUserData`, KLU plus
`IDASetJacFn`, iterative `IDASetJacTimes`, optional preconditioner callbacks,
and dense direct fallback.
The StableHLO action test covers the solver-gated rewrite to `enzyme.fwddiff`;
the unmarked direct sparse path is left explicit. The SUNDIALS op test covers
both explicit matrix and Jacobian-action IDA solve configurations plus the
parse/print form of `enzymexla.jacobian_materialization`. The synthesis test
checks that a complete materialization record produces an
`enzymexla.jacobian_action`, that an IDA solve requesting a Jacobian action is
linked to it, and that an explicit-matrix direct solve is left unchanged. The
effective-action synthesis test checks that matching `DfDy` and `DfDyp`
materialization records are paired into a compiler-synthesized IDA effective
Jacobian action before matrix-free selection. The matrix-free selection test
checks that explicit-matrix solves are retargeted only with the opt-in
attribute and a resolvable action, while non-opt-in or unmatched solves remain
explicit. The effective-action preference test checks that IDA matrix-free
selection chooses an action carrying
`enzymexla.sundials.ida_effective_jacobian_action` over a plain `DfDy` action
for the same materializer. The runtime-glue lowering test checks that a
selected matrix-free IDA solve emits SUNDIALS declarations, a generated
JacTimes callback symbol, and a registration helper with `SUNLinSol_SPGMR`,
`IDASetUserData`, `IDASetLinearSolver`, and `IDASetJacTimes`. The same test now
also covers context output-size discovery through `N_VGetLength`, the
semantic-action adapter path through `N_VScale`,
`N_VGetArrayPointer`, the generated raw-buffer kernel boundary, and the
callback-to-JVP-kernel delegation case when
`jacobian_action` resolves to an ABI-compatible LLVM function or to a unique
provenance-matching lowered raw-buffer kernel. The fwddiff raw-kernel test
checks that a semantic IDA effective action can generate a raw-buffer kernel
from recovered `DfDy` and `DfDyp` Enzyme `__enzyme_fwddiff` calls, including
context-input access and accumulation of `dF/dy * v + dF/dyp * (cj * v)`. The
runtime-glue rejection test checks that two lowered raw kernels advertising the
same semantic action fail instead of being selected arbitrarily. The semantic
lowering test checks that an IDA solve requiring a Jacobian action
rewrites its referenced action function to `enzyme.fwddiff`, while an
explicit-matrix direct solve leaves the materialized Jacobian path explicit.
The rejection test checks that unsupported matrix inspection prevents the
semantic JVP rewrite.

## Current Reactant Limitation

Loading the Bazel-built Reactant plugin directly into a separately built `opt`
currently fails before the pass runs because LLVM command-line options are
registered twice. The working path is the Reactant clang wrapper.

The full default Reactant CPU pipeline currently crashes in `ReactantNewPM` on
the GridKit harness after successfully writing the imported LLVM dialect MLIR.
This is why the export script uses a controlled override pipeline for the
repeatable artifact path and records the default-pipeline crash separately.

## Next Implementation Steps

1. Replace the remaining script-injected semantic solve bridge with an
   in-compiler bridge from GridKit's recovered `Ida::Jac` callback semantics to
   the synthesized Jacobian action records, or raise both source regions in one
   artifact so no overlay is needed.
2. Splice the generated context setup and teardown helpers into the host
   executable path, including model, residual input-array, and context-lifetime
   plumbing.
3. Run a full GridKit IDA simulation through the generated JVP path without
   requiring a manual `MatrixFreeJvp` or manual `IDASetJacTimes` call.
4. Either narrow the Reactant default pipeline around this source region or fix
   the `ReactantNewPM` crash so the marked GridKit path can rejoin the normal
   raising pipeline.
