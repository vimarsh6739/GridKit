/**
 * @file SystemModelGenClassicalSparseJacobianHarness.cpp
 *
 * Export-only harness for raising GridKit's existing SystemModel sparse
 * Jacobian path into LLVM IR and Reactant/MLIR. This keeps the application
 * source expression Jacobian-based: SystemModel::evaluateJacobian() calls the
 * existing component evaluateJacobian() implementations and assembles their COO
 * entries into the system CSR matrix.
 */

#include <cstddef>

#include <GridKit/Model/PhasorDynamics/Bus/BusEnzyme.cpp>
#include <GridKit/Model/PhasorDynamics/SystemModelImpl.hpp>
#include <GridKit/Model/PhasorDynamics/SynchronousMachine/GenClassical/GenClassicalEnzyme.cpp>

extern "C" std::size_t gridkit_systemmodel_genclassical_existing_sparse_jacobian()
{
  using ScalarT = double;
  using RealT   = double;
  using IdxT    = std::size_t;

  using BusDataT = GridKit::PhasorDynamics::BusData<RealT, IdxT>;
  using BusType  = BusDataT::BusType;
  using GenDataT = GridKit::PhasorDynamics::GenClassicalData<RealT, IdxT>;
  using GenBus   = GridKit::PhasorDynamics::GenClassicalBuses;
  using GenParam = GridKit::PhasorDynamics::GenClassicalParameters;
  using SystemDataT = GridKit::PhasorDynamics::SystemModelData<RealT, IdxT>;
  using SystemT     = GridKit::PhasorDynamics::SystemModel<ScalarT, IdxT>;

  SystemDataT data;

  BusDataT bus;
  bus.name     = "bus0";
  bus.bus_id   = 0;
  bus.bus_type = BusType::DEFAULT;
  bus.Vr0      = 1.04;
  bus.Vi0      = -0.08;
  data.bus.push_back(bus);

  GenDataT gen;
  gen.buses[GenBus::bus]            = 0;
  gen.parameters[GenParam::p0]      = 0.8;
  gen.parameters[GenParam::q0]      = 0.2;
  gen.parameters[GenParam::H]       = 3.5;
  gen.parameters[GenParam::D]       = 0.15;
  gen.parameters[GenParam::Ra]      = 0.0;
  gen.parameters[GenParam::Xdp]     = 0.22;
  gen.parameters[GenParam::mva]     = 100.0;
  data.genclassical.push_back(gen);

  SystemT system(data);
  system.allocate();
  system.initialize();
  system.evaluateResidual();
  system.evaluateJacobian();

  auto* jacobian = system.getCsrJacobian();
  return jacobian == nullptr ? 0 : static_cast<std::size_t>(jacobian->getNnz());
}
