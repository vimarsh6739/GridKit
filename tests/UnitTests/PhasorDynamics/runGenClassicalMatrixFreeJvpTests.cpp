#include <GridKit/Definitions.hpp>

#include <algorithm>
#include <iomanip>
#include <iostream>
#include <vector>

#include <GridKit/AutomaticDifferentiation/Enzyme/MatrixFreeJvp.hpp>
#include <GridKit/Model/PhasorDynamics/Bus/BusImpl.hpp>
#include <GridKit/Model/PhasorDynamics/SynchronousMachine/GenClassical/GenClassicalImpl.hpp>
#include <GridKit/Testing/Testing.hpp>

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

  namespace Testing
  {
    namespace
    {
      template <typename ScalarT>
      std::vector<ScalarT> perturb(const std::vector<ScalarT>& x,
                                   const std::vector<ScalarT>& seed,
                                   ScalarT                     scale)
      {
        auto result = x;
        for (size_t i = 0; i < result.size(); ++i)
        {
          result[i] += scale * seed[i];
        }
        return result;
      }

      template <typename ScalarT>
      bool compareVectors(const std::vector<ScalarT>& actual,
                          const std::vector<ScalarT>& expected,
                          ScalarT                     tol)
      {
        bool success = actual.size() == expected.size();
        if (!success)
        {
          std::cerr << "Size mismatch: actual=" << actual.size() << ", expected=" << expected.size() << "\n";
          return false;
        }

        for (size_t i = 0; i < actual.size(); ++i)
        {
          const bool entry_ok = isEqual(actual[i], expected[i], tol);
          success           *= entry_ok;
          if (!entry_ok)
          {
            std::cerr << "Mismatch at " << i << ": actual=" << std::setprecision(16) << actual[i]
                      << ", expected=" << expected[i] << "\n";
          }
        }

        return success;
      }
    } // namespace

    TestOutcome matrixFreeGenClassicalJvp()
    {
      using ScalarT = double;
      using IdxT    = size_t;
      using GenT    = PhasorDynamics::GenClassical<ScalarT, IdxT>;

      TestStatus success = true;

      PhasorDynamics::Bus<ScalarT, IdxT> bus(1.04, -0.08);
      GenT                               gen(&bus, 0.8, 0.2, 3.5, 0.15, 0.0, 0.22);

      bus.allocate();
      gen.allocate();
      bus.initialize();
      gen.initialize();

      success *= (gen.generatedJvpInput(0) == &gen);
      success *= (gen.generatedJvpInput(1) == static_cast<void*>(gen.y().data()));
      success *= (gen.generatedJvpInput(2) == static_cast<void*>(gen.yp().data()));
      auto* generated_wb =
        static_cast<ScalarT*>(gen.generatedJvpInput(3));
      success *= (generated_wb != nullptr);
      success *= isEqual(generated_wb[0], bus.y()[0]);
      success *= isEqual(generated_wb[1], bus.y()[1]);

      constexpr ScalarT cj  = 1.75;
      constexpr ScalarT eps = 1.0e-6;
      constexpr ScalarT tol = 2.0e-6;

      auto y  = gen.y();
      auto yp = gen.yp();
      auto wb = bus.y();

      std::vector<ScalarT> y_seed{0.25, -0.5, 0.75, -1.0, 1.25};
      std::vector<ScalarT> yp_seed(y_seed.size());
      std::transform(y_seed.begin(), y_seed.end(), yp_seed.begin(), [](ScalarT v)
                     { return cj * v; });
      std::vector<ScalarT> wb_seed{-0.375, 0.625};

      std::vector<ScalarT> internal_jvp(gen.size(), 0.0);
      std::vector<ScalarT> bus_jvp(bus.size(), 0.0);

      Enzyme::MatrixFree::ResidualJvp<GenT, Enzyme::Sparse::MemberFunctions::InternalResidual>::eval(&gen,
                                                                                                      internal_jvp.size(),
                                                                                                      y.data(),
                                                                                                      y_seed.data(),
                                                                                                      yp.data(),
                                                                                                      yp_seed.data(),
                                                                                                      wb.data(),
                                                                                                      wb_seed.data(),
                                                                                                      internal_jvp.data());
      Enzyme::MatrixFree::ResidualJvp<GenT, Enzyme::Sparse::MemberFunctions::BusResidual>::eval(&gen,
                                                                                                bus_jvp.size(),
                                                                                                y.data(),
                                                                                                y_seed.data(),
                                                                                                yp.data(),
                                                                                                yp_seed.data(),
                                                                                                wb.data(),
                                                                                                wb_seed.data(),
                                                                                                bus_jvp.data());

      const auto y_plus   = perturb(y, y_seed, eps);
      const auto y_minus  = perturb(y, y_seed, -eps);
      const auto yp_plus  = perturb(yp, yp_seed, eps);
      const auto yp_minus = perturb(yp, yp_seed, -eps);
      const auto wb_plus  = perturb(wb, wb_seed, eps);
      const auto wb_minus = perturb(wb, wb_seed, -eps);

      std::vector<ScalarT> f_plus(gen.size(), 0.0);
      std::vector<ScalarT> f_minus(gen.size(), 0.0);
      std::vector<ScalarT> h_plus(bus.size(), 0.0);
      std::vector<ScalarT> h_minus(bus.size(), 0.0);
      gen.evaluateInternalResidual(y_plus.data(), yp_plus.data(), wb_plus.data(), f_plus.data());
      gen.evaluateInternalResidual(y_minus.data(), yp_minus.data(), wb_minus.data(), f_minus.data());
      gen.evaluateBusResidual(y_plus.data(), yp_plus.data(), wb_plus.data(), h_plus.data());
      gen.evaluateBusResidual(y_minus.data(), yp_minus.data(), wb_minus.data(), h_minus.data());

      std::vector<ScalarT> internal_fd(gen.size(), 0.0);
      std::vector<ScalarT> bus_fd(bus.size(), 0.0);
      for (size_t i = 0; i < internal_fd.size(); ++i)
      {
        internal_fd[i] = (f_plus[i] - f_minus[i]) / (2.0 * eps);
      }
      for (size_t i = 0; i < bus_fd.size(); ++i)
      {
        bus_fd[i] = (h_plus[i] - h_minus[i]) / (2.0 * eps);
      }

      success *= compareVectors(internal_jvp, internal_fd, tol);
      success *= compareVectors(bus_jvp, bus_fd, tol);

      return success.report(__func__);
    }
  } // namespace Testing
} // namespace GridKit

int main()
{
  GridKit::Testing::TestingResults result;
  result += GridKit::Testing::matrixFreeGenClassicalJvp();
  return result.summary();
}
