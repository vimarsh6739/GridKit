#include <iostream>

#include <GridKit/Model/PhasorDynamics/Bus/BusImpl.hpp>
#include <GridKit/Model/PhasorDynamics/SynchronousMachine/GenClassical/GenClassicalImpl.hpp>
#include <GridKit/Solver/Dynamic/Ida.hpp>
#include <GridKit/Solver/Dynamic/IdaJvpRuntime.hpp>

namespace GridKit
{
  namespace PhasorDynamics
  {
    template <typename scalar_type, typename index_type>
    int Bus<scalar_type, index_type>::evaluateJacobian()
    {
      return 0;
    }

    template <typename scalar_type, typename index_type>
    int GenClassical<scalar_type, index_type>::evaluateJacobian()
    {
      return 0;
    }
  } // namespace PhasorDynamics
} // namespace GridKit

extern "C"
{
  int enzyme_const     = 0;
  int enzyme_dup       = 1;
  int enzyme_dupnoneed = 2;
}

int main()
{
  using ScalarT = double;
  using IdxT    = long;
  using BusT    = GridKit::PhasorDynamics::Bus<ScalarT, IdxT>;
  using GenT    = GridKit::PhasorDynamics::GenClassical<ScalarT, IdxT>;
  using IdaT    = AnalysisManager::Sundials::Ida<ScalarT, IdxT>;

  BusT bus(1.04, -0.08);
  GenT gen(&bus, 0.8, 0.2, 3.5, 0.15, 0.0, 0.22);

  bus.allocate();
  gen.allocate();
  bus.initialize();
  gen.initialize();

  if (!AnalysisManager::Sundials::Runtime::hasGeneratedIdaJvpHostSplice())
  {
    std::cerr << "generated IDA JVP host splice symbols missing\n";
    return 1;
  }

  IdaT ida(&gen);
  if (ida.configureSimulation() != 0)
  {
    std::cerr << "configureSimulation failed\n";
    return 1;
  }
  if (ida.initializeSimulation(0.0) != 0)
  {
    std::cerr << "initializeSimulation failed\n";
    return 1;
  }
  if (ida.runSimulation(0.01, 2) != 0)
  {
    std::cerr << "runSimulation failed\n";
    return 1;
  }

  std::cout << "generated real SUNDIALS component smoke: ok\n";
  return 0;
}
