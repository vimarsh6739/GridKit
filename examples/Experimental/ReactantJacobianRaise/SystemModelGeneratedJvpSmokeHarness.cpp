#include <algorithm>
#include <cmath>
#include <cstddef>
#include <iomanip>
#include <iostream>
#include <vector>

#include <GridKit/Model/PhasorDynamics/Bus/BusImpl.hpp>
#include <GridKit/Model/PhasorDynamics/SystemModelImpl.hpp>
#include <GridKit/Model/PhasorDynamics/SynchronousMachine/GenClassical/GenClassicalImpl.hpp>

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

namespace
{
  using ScalarT = double;
  using IdxT    = long;
  using BusT    = GridKit::PhasorDynamics::Bus<ScalarT, IdxT>;
  using GenT    = GridKit::PhasorDynamics::GenClassical<ScalarT, IdxT>;
  using SystemT = GridKit::PhasorDynamics::SystemModel<ScalarT, IdxT>;

  class ResidualOnlySystem : public SystemT
  {
  public:
    bool hasJacobian() override
    {
      return false;
    }
  };

  bool check(bool condition, const char* message)
  {
    if (!condition)
    {
      std::cerr << "systemmodel generated JVP smoke failed: " << message << '\n';
    }
    return condition;
  }

  std::vector<double> perturb(const std::vector<double>& values,
                              const std::vector<double>& seed,
                              double                     scale)
  {
    auto result = values;
    for (std::size_t index = 0; index < result.size(); ++index)
    {
      result[index] += scale * seed[index];
    }
    return result;
  }

  bool compareVectors(const std::vector<double>& actual,
                      const std::vector<double>& expected,
                      double                     tolerance)
  {
    if (actual.size() != expected.size())
    {
      std::cerr << "size mismatch: actual=" << actual.size()
                << ", expected=" << expected.size() << '\n';
      return false;
    }

    bool success = true;
    for (std::size_t index = 0; index < actual.size(); ++index)
    {
      const double diff = std::abs(actual[index] - expected[index]);
      if (diff > tolerance)
      {
        std::cerr << "mismatch at " << index << ": actual="
                  << std::setprecision(17) << actual[index]
                  << ", expected=" << expected[index]
                  << ", diff=" << diff << '\n';
        success = false;
      }
    }
    return success;
  }

  void evaluateSystemResidual(SystemT&                  system,
                              const std::vector<double>& y,
                              const std::vector<double>& yp,
                              std::vector<double>&       residual)
  {
    std::copy(y.begin(), y.end(), system.y().begin());
    std::copy(yp.begin(), yp.end(), system.yp().begin());
    system.evaluateResidual();
    std::copy(system.getResidual().begin(),
              system.getResidual().end(),
              residual.begin());
  }

  void evaluateSystemLayoutResidual(GenT&                      gen,
                                    const std::vector<double>& y,
                                    const std::vector<double>& yp,
                                    std::vector<double>&       residual)
  {
    residual[0] = 0.0;
    residual[1] = 0.0;
    gen.evaluateBusResidual(y.data() + 2, yp.data() + 2, y.data(), residual.data());
    gen.evaluateInternalResidual(y.data() + 2, yp.data() + 2, y.data(), residual.data() + 2);
  }
} // namespace

extern "C" void gridkitGeneratedSystemModelLayoutJvp(
    GenT*,
    double*,
    double*,
    double*,
    double*,
    double*);

extern "C" void gridkitGeneratedSystemModelLayoutExplicitSparseJvp(
    GenT*,
    const IdxT*,
    const IdxT*,
    double*,
    double*,
    double,
    double*,
    double*);

extern "C" void gridkitGeneratedSystemModelLayoutMatrixFreeJvp(
    GenT*,
    double*,
    double*,
    double*,
    double*,
    double*);

extern "C"
{
  int enzyme_const     = 0;
  int enzyme_dup       = 1;
  int enzyme_dupnoneed = 2;
}

int main()
{
  constexpr double cj  = 1.75;
  constexpr double eps = 1.0e-6;
  constexpr double tol = 4.0e-6;

  BusT bus(1.04, -0.08);
  GenT gen(&bus, 0.8, 0.2, 3.5, 0.15, 0.0, 0.22);
  ResidualOnlySystem system;
  system.addBus(&bus);
  system.addComponent(&gen);
  system.allocate();
  system.initialize();
  system.updateTime(0.125, cj);

  std::vector<double> y  = system.y();
  std::vector<double> yp = system.yp();

  std::vector<double> primal_from_system(system.size(), 0.0);
  std::vector<double> primal_from_layout(system.size(), 0.0);
  evaluateSystemResidual(system, y, yp, primal_from_system);
  evaluateSystemLayoutResidual(gen, y, yp, primal_from_layout);
  if (!check(compareVectors(primal_from_layout, primal_from_system, tol),
             "layout residual does not match SystemModel residual"))
  {
    return 1;
  }

  std::vector<double> v{0.125, -0.25, 0.375, -0.5, 0.625, -0.75, 0.875};
  std::vector<double> yp_seed(v.size());
  std::transform(v.begin(), v.end(), yp_seed.begin(), [](double value)
                 { return cj * value; });

  std::vector<double> generated_jv(system.size(), 0.0);
  std::vector<double> explicit_sparse_jv(system.size(), 0.0);
  std::vector<double> matrix_free_jv(system.size(), 0.0);

  gridkitGeneratedSystemModelLayoutJvp(&gen,
                                       y.data(),
                                       v.data(),
                                       yp.data(),
                                       yp_seed.data(),
                                       generated_jv.data());

  const IdxT internal_residual_indices[] = {2, 3, 4, 5, 6};
  const IdxT internal_variable_indices[] = {2, 3, 4, 5, 6};
  gridkitGeneratedSystemModelLayoutExplicitSparseJvp(&gen,
                                                     internal_residual_indices,
                                                     internal_variable_indices,
                                                     y.data(),
                                                     yp.data(),
                                                     cj,
                                                     v.data(),
                                                     explicit_sparse_jv.data());

  gridkitGeneratedSystemModelLayoutMatrixFreeJvp(&gen,
                                                 y.data(),
                                                 v.data(),
                                                 yp.data(),
                                                 yp_seed.data(),
                                                 matrix_free_jv.data());

  const auto y_plus   = perturb(y, v, eps);
  const auto y_minus  = perturb(y, v, -eps);
  const auto yp_plus  = perturb(yp, yp_seed, eps);
  const auto yp_minus = perturb(yp, yp_seed, -eps);

  std::vector<double> f_plus(system.size(), 0.0);
  std::vector<double> f_minus(system.size(), 0.0);
  evaluateSystemLayoutResidual(gen, y_plus, yp_plus, f_plus);
  evaluateSystemLayoutResidual(gen, y_minus, yp_minus, f_minus);

  std::vector<double> finite_difference(system.size(), 0.0);
  for (std::size_t index = 0; index < finite_difference.size(); ++index)
  {
    finite_difference[index] = (f_plus[index] - f_minus[index]) / (2.0 * eps);
  }

  const bool finite_difference_match =
      compareVectors(generated_jv, finite_difference, tol);
  const bool explicit_sparse_match =
      compareVectors(generated_jv, explicit_sparse_jv, tol);
  const bool matrix_free_match =
      compareVectors(generated_jv, matrix_free_jv, tol);

  if (!check(finite_difference_match,
             "generated SystemModel-layout JVP did not match finite difference") ||
      !check(explicit_sparse_match,
             "generated SystemModel-layout JVP did not match explicit sparse J*v") ||
      !check(matrix_free_match,
             "generated SystemModel-layout JVP did not match MatrixFree oracle"))
  {
    return 1;
  }

  std::cout << "systemmodel generated JVP smoke: ok finite_difference=ok"
            << " explicit_sparse_oracle=ok matrix_free_oracle=ok\n";
  return 0;
}
