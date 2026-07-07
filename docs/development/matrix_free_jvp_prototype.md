# Matrix-Free Enzyme JVP Prototype

This note records the current explicit-Jacobian path, the prototype matrix-free
JVP path, and the smallest follow-on API needed to connect GridKit to SUNDIALS
matrix-free linear solvers.

## Current Explicit Jacobian Path

GridKit's Enzyme sparse Jacobian path starts at the common intrinsic declaration.
The current call graph, from SUNDIALS registration to Enzyme residual
differentiation, is:

```text
Ida::configureSimulation()
  -> IDAInit(..., Ida::Residual, ...)
  -> IDASetUserData(..., model_)
  -> Ida::configureLinearSolver()
    -> Ida::configureLinearSolverSparse()
      -> SUNSparseMatrix(...)
      -> SUNLinSol_KLU(...)
      -> IDASetLinearSolver(solver_, linearSolver_, JacobianMat_)
      -> IDASetJacFn(solver_, Ida::Jac)

IDA calls Ida::Jac(t, cj, yy, yp, ..., J, user_data, ...)
  -> copyVec(yy, model->y())
  -> copyVec(yp, model->yp())
  -> model->updateTime(t, cj)
  -> model->evaluateJacobian()
    -> SystemModel::evaluateJacobian()
      -> bus->evaluateJacobian()
      -> component->evaluateJacobian()
        -> GenClassical::evaluateJacobian() and equivalent Enzyme component overrides
          -> Sparse::DfDy<..., InternalResidual>::eval(...)
            -> Sparse::__enzyme_fwddiff(..., Sparse::ModelWrapper<..., InternalResidual>::eval, ...)
              -> model->evaluateInternalResidual(...)
          -> Sparse::DfDyp<..., InternalResidual>::eval(...)
            -> Sparse::__enzyme_fwddiff(..., Sparse::ModelWrapper<..., InternalResidual>::eval, ...)
              -> model->evaluateInternalResidual(...)
          -> Sparse::DfDwb<..., InternalResidual>::eval(...)
            -> Sparse::__enzyme_fwddiff(..., Sparse::ModelWrapper<..., InternalResidual>::eval, ...)
              -> model->evaluateInternalResidual(...)
          -> Sparse::DhDy<..., BusResidual>::eval(...)
            -> Sparse::__enzyme_fwddiff(..., Sparse::ModelWrapper<..., BusResidual>::eval, ...)
              -> model->evaluateBusResidual(...)
          -> component->constructCoo()
      -> gather component COO and bus COO into SystemModel CSR
  -> model->getCsrJacobian()
  -> SUNMatZero(J)
  -> copy GridKit CSR row pointers, columns, and values into SUNSparseMatrix
```

The same sparse helper shape is used by the other Enzyme component overrides.
`DfDws` and `DhDwb` cover signal and bus-coupling variants for components that
need them, and the branch residual wrappers use `BusResidual11`,
`BusResidual12`, `BusResidual21`, and `BusResidual22`.

No existing GridKit interface applies a Jacobian to a vector without first
materializing the Jacobian. `Model::Evaluator` exposes `evaluateJacobian()` and
`getCsrJacobian()`, and `Ida` currently has dense and sparse matrix-based linear
solver paths only.

## Prototype JVP Path

`GridKit/AutomaticDifferentiation/Enzyme/MatrixFreeJvp.hpp` adds
`GridKit::Enzyme::MatrixFree::ResidualJvp<ModelT, function>`.

The helper reuses the existing `Sparse::ModelWrapper` residual entry points, but
passes arbitrary seed vectors instead of one-hot seeds:

```text
residual_seed =
    d residual / d y  * y_seed
  + d residual / d yp * yp_seed
  + d residual / d wb * wb_seed
```

For an IDA Jacobian \(J = dF/dy + cj * dF/dyp\), the caller supplies
`y_seed = v` and `yp_seed = cj * v` for variables represented by IDA's solution
vector. Coupling variables use the relevant slice of `v` as their seed.

The focused test
`tests/UnitTests/PhasorDynamics/runGenClassicalMatrixFreeJvpTests.cpp` builds a
standalone GenClassical residual test, computes internal and bus residual JVPs
through Enzyme, and checks both against central finite differences of the same
residual methods. It intentionally avoids `evaluateJacobian()` and sparse CSR
construction so the matrix-free prototype is independent of the legacy sparse
Jacobian materialization path.

## SUNDIALS Matrix-Free Interface

IDA's matrix-based path passes a non-null `SUNMatrix` to `IDASetLinearSolver`
and may register an explicit Jacobian callback with `IDASetJacFn`.

For matrix-free IDA integration:

1. Create an iterative `SUNLinearSolver`, such as a SUNDIALS Krylov solver.
2. Call `IDASetLinearSolver(ida_mem, LS, NULL)`. The third argument is `NULL`
   because a matrix-free linear solver only needs \(Jv\), not stored matrix
   entries.
3. Register the Jacobian-vector product with
   `IDASetJacTimes(ida_mem, jsetup, jtimes)`.
4. Implement `IDALsJacTimesVecFn`:

```c
int jtimes(sunrealtype tt,
           N_Vector yy,
           N_Vector yp,
           N_Vector rr,
           N_Vector v,
           N_Vector Jv,
           sunrealtype cj,
           void* user_data,
           N_Vector tmp1,
           N_Vector tmp2);
```

The callback computes \(Jv = (dF/dy + cj * dF/dyp)v\). A setup callback
`IDALsJacTimesSetupFn` is optional and can be `NULL` if the JVP path needs no
cached setup. Iterative solvers may also use `IDASetPreconditioner(psetup,
psolve)`; that is orthogonal to the matrix-free JVP and can initially be omitted
or backed by a separate approximate preconditioner.

## Smallest Glue to SUNDIALS

The minimal reusable GridKit abstraction should be a system-level operator on
the model side:

```c++
int applyJacobianVector(RealT t,
                        RealT cj,
                        const std::vector<ScalarT>& y,
                        const std::vector<ScalarT>& yp,
                        const std::vector<ScalarT>& v,
                        std::vector<ScalarT>& Jv);
```

That operator belongs in GridKit, not in `Ida`, because it must understand
GridKit's component and bus scattering rules:

1. Update component and bus primal variables from the global `y` and `yp`.
2. For each component, gather local `y_seed`, `yp_seed`, bus coupling seed
   `wb_seed`, and signal seed `ws_seed` from the global vector `v`.
3. Use `yp_seed = cj * y_seed` for IDA variables.
4. Call `ResidualJvp` for internal residual and bus residual blocks.
5. Scatter/add local residual tangents into the global `Jv` using residual
   indices, preserving the current residual assembly convention where buses are
   initialized first and components add bus-current contributions.

The SUNDIALS adapter then stays thin:

1. `Ida::configureLinearSolverMatrixFree()` creates the iterative solver.
2. It calls `IDASetLinearSolver(solver_, linearSolver_, NULL)`.
3. It calls `IDASetJacTimes(solver_, nullptr, Ida::JacTimes)`.
4. `Ida::JacTimes(...)` copies or aliases `yy`, `yp`, `v`, and `Jv`, then
   delegates to `model_->applyJacobianVector(...)`.

## Ownership Recommendation

- **GridKit** owns the residual JVP abstraction, the system-level scatter/gather
  operator, and the SUNDIALS `Ida::JacTimes` adapter because they depend on
  GridKit's model indexing and residual assembly.
- **Reactant** should not change for this prototype. It may later target the
  GridKit system-level operator if the same runtime API is useful beyond
  SUNDIALS.
- **Enzyme-JAX** should not change for this prototype; it does not own GridKit
  residual layout or SUNDIALS callbacks.
- **Enzyme** changes are only needed if the compiler/plugin compatibility or
  sparse Enzyme crash seen during local verification must be fixed upstream.
- A **standalone reusable runtime** is premature. The first reusable boundary is
  the GridKit-level `applyJacobianVector` contract above.

## Modified Files for the Prototype

- `GridKit/AutomaticDifferentiation/Enzyme/MatrixFreeJvp.hpp`
- `tests/UnitTests/PhasorDynamics/runGenClassicalMatrixFreeJvpTests.cpp`
- `tests/UnitTests/PhasorDynamics/CMakeLists.txt`
- `cmake/FindEnzyme.cmake`
- `docs/development/matrix_free_jvp_prototype.md`

## Verification Notes

The prototype was built with an Enzyme-enabled `enzyme-clang++` wrapper and the
shared Clang plugin disabled via `GRIDKIT_ENZYME_USE_CLANG_PLUGIN=OFF`.

Validated checks:

```text
ctest --test-dir GridKit/build/gridkit-enzyme-jvp-wrapper \
  -R PhasorDynamicsGenClassicalMatrixFreeJvpTest --output-on-failure
```

The default non-Enzyme GenClassical unit test was also rebuilt and run to ensure
the experimental Enzyme-only test target does not affect the normal path.

Known local toolchain issue: the existing shared `ClangEnzyme-23.so` and
`LLVMEnzyme-23.so` artifacts are ABI-incompatible with the available Clang/LLVM
binary in this workspace. The Bazel-built `enzyme-clang++` wrapper can compile
the matrix-free prototype, but the legacy sparse GenClassical Enzyme translation
unit crashes in Enzyme's sparse lowering under that wrapper. The standalone JVP
test avoids the sparse lowering path by design.
