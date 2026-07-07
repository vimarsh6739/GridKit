/**
 * @file GenClassicalSparseJacobianHarness.cpp
 *
 * Export-only harness for raising GridKit's existing Enzyme sparse Jacobian
 * path into LLVM IR and, from there, Reactant/MLIR.
 *
 * This file deliberately includes the existing Enzyme Jacobian translation
 * units. It is not meant to introduce a new runtime API; it gives compiler
 * experiments one small, closed source region that still calls
 * GenClassical::evaluateJacobian().
 */

#include <cstddef>

#include <GridKit/Model/PhasorDynamics/Bus/BusEnzyme.cpp>
#include <GridKit/Model/PhasorDynamics/SynchronousMachine/GenClassical/GenClassicalEnzyme.cpp>

extern "C" std::size_t gridkit_genclassical_existing_sparse_jacobian()
{
  using ScalarT = double;
  using IdxT    = std::size_t;
  using BusT    = GridKit::PhasorDynamics::Bus<ScalarT, IdxT>;
  using GenT    = GridKit::PhasorDynamics::GenClassical<ScalarT, IdxT>;

  BusT bus(1.04, -0.08);
  GenT gen(&bus, 0.8, 0.2, 3.5, 0.15, 0.0, 0.22);

  bus.allocate();
  gen.allocate();
  bus.initialize();
  gen.initialize();

  bus.evaluateJacobian();
  gen.evaluateJacobian();

  return static_cast<std::size_t>(gen.nnz());
}
