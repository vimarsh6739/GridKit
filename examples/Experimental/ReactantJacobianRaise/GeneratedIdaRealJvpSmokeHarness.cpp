#include <algorithm>
#include <cmath>
#include <cstdint>
#include <iomanip>
#include <iostream>
#include <vector>

#include <GridKit/Model/PhasorDynamics/Bus/BusImpl.hpp>
#include <GridKit/Model/PhasorDynamics/SynchronousMachine/GenClassical/GenClassicalImpl.hpp>
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

namespace
{
  using ScalarT = double;
  using IdxT    = long;
  using GenT    = GridKit::PhasorDynamics::GenClassical<ScalarT, IdxT>;
  using EvalT   = GridKit::Model::Evaluator<ScalarT, IdxT>;

  struct SmokeVector
  {
    std::int64_t length{};
    double*      data{};
  };

  using SmokeJacTimesFn = int (*)(double,
                                  void*,
                                  void*,
                                  void*,
                                  void*,
                                  void*,
                                  double,
                                  void*,
                                  void*,
                                  void*);

  struct SmokeLinearSolver
  {
    SmokeVector* template_vector{};
    int          pretype{};
    int          maxl{};
    void*        sunctx{};
  };

  struct SmokeIdaMem
  {
    void*           user_data{};
    void*           linear_solver{};
    void*           matrix{};
    SmokeJacTimesFn jac_times{};
    int             set_user_data_calls{};
    int             set_linear_solver_calls{};
    int             set_jac_times_calls{};
  };

  int sun_linear_solver_allocations = 0;
  int sun_linear_solver_frees       = 0;

  bool check(bool condition, const char* message)
  {
    if (!condition)
    {
      std::cerr << "generated real JVP smoke failed: " << message << '\n';
    }
    return condition;
  }

  void* generatedInputResolver(void* model, std::int64_t input_index)
  {
    auto* typed_model = static_cast<EvalT*>(model);
    return typed_model == nullptr ? nullptr : typed_model->generatedJvpInput(input_index);
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
} // namespace

extern "C" std::int64_t N_VGetLength(void* vector)
{
  auto* typed_vector = static_cast<SmokeVector*>(vector);
  return typed_vector == nullptr ? 0 : typed_vector->length;
}

extern "C" double* N_VGetArrayPointer(void* vector)
{
  auto* typed_vector = static_cast<SmokeVector*>(vector);
  return typed_vector == nullptr ? nullptr : typed_vector->data;
}

extern "C" void N_VScale(double scale, void* source, void* destination)
{
  auto* source_vector      = static_cast<SmokeVector*>(source);
  auto* destination_vector = static_cast<SmokeVector*>(destination);
  if (source_vector == nullptr || destination_vector == nullptr ||
      source_vector->data == nullptr || destination_vector->data == nullptr)
  {
    return;
  }

  const std::int64_t length =
      std::min(source_vector->length, destination_vector->length);
  for (std::int64_t index = 0; index < length; ++index)
  {
    destination_vector->data[index] = scale * source_vector->data[index];
  }
}

extern "C" int IDASetUserData(void* ida_mem, void* user_data)
{
  auto* typed_ida_mem = static_cast<SmokeIdaMem*>(ida_mem);
  if (typed_ida_mem == nullptr)
  {
    return 1;
  }

  typed_ida_mem->user_data = user_data;
  ++typed_ida_mem->set_user_data_calls;
  return 0;
}

extern "C" void* SUNLinSol_SPGMR(void* template_vector,
                                 int   pretype,
                                 int   maxl,
                                 void* sunctx)
{
  auto* linear_solver            = new SmokeLinearSolver{};
  linear_solver->template_vector = static_cast<SmokeVector*>(template_vector);
  linear_solver->pretype         = pretype;
  linear_solver->maxl            = maxl;
  linear_solver->sunctx          = sunctx;
  ++sun_linear_solver_allocations;
  return linear_solver;
}

extern "C" int SUNLinSolFree(void* linear_solver)
{
  auto* typed_linear_solver = static_cast<SmokeLinearSolver*>(linear_solver);
  if (typed_linear_solver == nullptr)
  {
    return 0;
  }

  delete typed_linear_solver;
  ++sun_linear_solver_frees;
  return 0;
}

extern "C" int IDASetLinearSolver(void* ida_mem,
                                  void* linear_solver,
                                  void* matrix)
{
  auto* typed_ida_mem = static_cast<SmokeIdaMem*>(ida_mem);
  if (typed_ida_mem == nullptr || linear_solver == nullptr)
  {
    return 1;
  }

  typed_ida_mem->linear_solver = linear_solver;
  typed_ida_mem->matrix        = matrix;
  ++typed_ida_mem->set_linear_solver_calls;
  return 0;
}

extern "C" int IDASetJacTimes(void* ida_mem,
                              void* /*jac_times_setup*/,
                              void* jac_times)
{
  auto* typed_ida_mem = static_cast<SmokeIdaMem*>(ida_mem);
  if (typed_ida_mem == nullptr || jac_times == nullptr)
  {
    return 1;
  }

  typed_ida_mem->jac_times = reinterpret_cast<SmokeJacTimesFn>(jac_times);
  ++typed_ida_mem->set_jac_times_calls;
  return 0;
}

extern "C"
{
  int enzyme_const     = 0;
  int enzyme_dup       = 1;
  int enzyme_dupnoneed = 2;
}

int main()
{
  using AnalysisManager::Sundials::Runtime::collectGeneratedIdaJvpInputs;
  using AnalysisManager::Sundials::Runtime::configureGeneratedIdaJvp;
  using AnalysisManager::Sundials::Runtime::hasGeneratedIdaJvpHostSplice;
  using AnalysisManager::Sundials::Runtime::teardownGeneratedIdaJvp;

  GridKit::PhasorDynamics::Bus<ScalarT, IdxT> bus(1.04, -0.08);
  GenT gen(&bus, 0.8, 0.2, 3.5, 0.15, 0.0, 0.22);

  bus.allocate();
  gen.allocate();
  bus.initialize();
  gen.initialize();

  if (!check(hasGeneratedIdaJvpHostSplice(), "generated hook symbols missing"))
  {
    return 1;
  }

  std::vector<void*> inputs =
      collectGeneratedIdaJvpInputs(&gen, &generatedInputResolver);
  if (!check(inputs.size() == 4, "generated input provider returned wrong size") ||
      !check(inputs[0] == &gen, "generated input provider missed model") ||
      !check(inputs[3] != nullptr, "generated input provider missed work buffer"))
  {
    return 1;
  }

  std::vector<double> y  = gen.y();
  std::vector<double> yp = gen.yp();
  const auto*         wb_ptr = static_cast<const double*>(inputs[3]);
  std::vector<double> wb{wb_ptr[0], wb_ptr[1]};

  constexpr double cj  = 1.75;
  constexpr double eps = 1.0e-6;
  constexpr double tol = 3.0e-6;

  std::vector<double> v{0.25, -0.5, 0.75, -1.0, 1.25};
  std::vector<double> yp_seed(v.size());
  std::transform(v.begin(), v.end(), yp_seed.begin(), [](double value)
                 { return cj * value; });

  std::vector<double> residual(y.size(), 0.0);
  std::vector<double> jv(y.size(), 0.0);
  std::vector<double> tmp1(y.size(), 0.0);
  std::vector<double> tmp2(y.size(), 0.0);

  SmokeVector yy{static_cast<std::int64_t>(y.size()), y.data()};
  SmokeVector yp_vector{static_cast<std::int64_t>(yp.size()), yp.data()};
  SmokeVector rr{static_cast<std::int64_t>(residual.size()), residual.data()};
  SmokeVector vv{static_cast<std::int64_t>(v.size()), v.data()};
  SmokeVector jv_vector{static_cast<std::int64_t>(jv.size()), jv.data()};
  SmokeVector tmp1_vector{static_cast<std::int64_t>(tmp1.size()), tmp1.data()};
  SmokeVector tmp2_vector{static_cast<std::int64_t>(tmp2.size()), tmp2.data()};

  SmokeIdaMem ida_mem{};
  int         sunctx_token = 0;
  void*       generated_context{};

  int status =
      configureGeneratedIdaJvp(&ida_mem,
                               &yy,
                               &sunctx_token,
                               &gen,
                               inputs.data(),
                               static_cast<std::int64_t>(inputs.size()),
                               &generated_context);
  if (!check(status == 0, "generated setup returned failure") ||
      !check(generated_context != nullptr, "generated setup did not create context") ||
      !check(ida_mem.user_data == generated_context, "generated setup did not install context") ||
      !check(ida_mem.linear_solver != nullptr, "generated setup did not create linear solver") ||
      !check(ida_mem.matrix == nullptr, "generated setup should be matrix-free") ||
      !check(ida_mem.jac_times != nullptr, "generated setup did not register JacTimes") ||
      !check(ida_mem.set_user_data_calls == 1, "unexpected IDASetUserData calls") ||
      !check(ida_mem.set_linear_solver_calls == 1, "unexpected IDASetLinearSolver calls") ||
      !check(ida_mem.set_jac_times_calls == 1, "unexpected IDASetJacTimes calls") ||
      !check(sun_linear_solver_allocations == 1, "unexpected SUNLinSol_SPGMR calls"))
  {
    teardownGeneratedIdaJvp(&ida_mem);
    return 1;
  }

  status = ida_mem.jac_times(0.125,
                             &yy,
                             &yp_vector,
                             &rr,
                             &vv,
                             &jv_vector,
                             cj,
                             generated_context,
                             &tmp1_vector,
                             &tmp2_vector);
  if (!check(status == 0, "generated JacTimes callback returned failure"))
  {
    teardownGeneratedIdaJvp(&ida_mem);
    return 1;
  }

  const auto y_plus   = perturb(y, v, eps);
  const auto y_minus  = perturb(y, v, -eps);
  const auto yp_plus  = perturb(yp, yp_seed, eps);
  const auto yp_minus = perturb(yp, yp_seed, -eps);
  std::vector<double> f_plus(y.size(), 0.0);
  std::vector<double> f_minus(y.size(), 0.0);
  gen.evaluateInternalResidual(y_plus.data(), yp_plus.data(), wb.data(), f_plus.data());
  gen.evaluateInternalResidual(y_minus.data(), yp_minus.data(), wb.data(), f_minus.data());

  std::vector<double> finite_difference(y.size(), 0.0);
  for (std::size_t index = 0; index < finite_difference.size(); ++index)
  {
    finite_difference[index] = (f_plus[index] - f_minus[index]) / (2.0 * eps);
  }

  const bool vectors_match = compareVectors(jv, finite_difference, tol);
  teardownGeneratedIdaJvp(&ida_mem);
  if (!check(sun_linear_solver_frees == 1,
             "generated teardown did not release remembered linear solver") ||
      !check(vectors_match, "generated JVP did not match finite difference"))
  {
    return 1;
  }

  std::cout << "generated real JVP smoke: ok\n";
  return 0;
}
