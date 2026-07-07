#include <iostream>

#include <GridKit/Model/PhasorDynamics/Bus/BusImpl.hpp>
#include <GridKit/Model/PhasorDynamics/SynchronousMachine/GenClassical/GenClassicalImpl.hpp>
#include <GridKit/Solver/Dynamic/Ida.hpp>
#include <GridKit/Solver/Dynamic/IdaJvpRuntime.hpp>

namespace
{
  long explicit_jacobian_calls = 0;
}

namespace GridKit
{
  namespace PhasorDynamics
  {
    template <typename scalar_type, typename index_type>
    int Bus<scalar_type, index_type>::evaluateJacobian()
    {
      ++explicit_jacobian_calls;
      return 1;
    }

    template <typename scalar_type, typename index_type>
    int GenClassical<scalar_type, index_type>::evaluateJacobian()
    {
      ++explicit_jacobian_calls;
      return 1;
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
  if (!ida.generatedJvpConfigured())
  {
    std::cerr << "generated IDA JVP path was not configured\n";
    return 1;
  }

  gen.setPmech(0.82);
  bus.Vr() += 1.0e-3;
  bus.Vi() -= 5.0e-4;

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

  const auto ida_stats = ida.getStats();
  const auto lin_stats = ida.getLinearSolverStats();
  if (explicit_jacobian_calls != 0)
  {
    std::cerr << "legacy explicit Jacobian path was invoked "
              << explicit_jacobian_calls << " time(s)\n";
    return 1;
  }
  if (lin_stats.num_jacobian_evals_ != 0)
  {
    std::cerr << "SUNDIALS reported explicit Jacobian evaluations: "
              << lin_stats.num_jacobian_evals_ << '\n';
    return 1;
  }
  if (lin_stats.num_jac_times_evals_ <= 0)
  {
    std::cerr << "SUNDIALS did not report any JacTimes evaluations\n";
    return 1;
  }
  if (lin_stats.num_linear_iters_ <= 0)
  {
    std::cerr << "SUNDIALS did not report iterative linear solves\n";
    return 1;
  }

  std::cout << "generated real SUNDIALS component smoke: ok"
            << " steps=" << ida_stats.num_steps_
            << " residual_evals=" << ida_stats.num_residual_evals_
            << " nonlinear_iters=" << ida_stats.num_nonlinear_iters_
            << " linear_iters=" << lin_stats.num_linear_iters_
            << " jac_times_evals=" << lin_stats.num_jac_times_evals_
            << " explicit_jacobian_evals=" << lin_stats.num_jacobian_evals_
            << '\n';
  return 0;
}
