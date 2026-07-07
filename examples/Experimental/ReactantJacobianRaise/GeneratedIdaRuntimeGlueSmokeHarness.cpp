#include <algorithm>
#include <cstdint>
#include <iostream>
#include <vector>

#include <GridKit/Solver/Dynamic/IdaJvpRuntime.hpp>

namespace
{
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

  struct SmokeModel
  {
    double work{};
  };

  int sun_linear_solver_allocations = 0;
  int sun_linear_solver_frees       = 0;

  bool check(bool condition, const char* message)
  {
    if (!condition)
    {
      std::cerr << "generated runtime glue smoke failed: " << message << '\n';
    }
    return condition;
  }

  void* smokeInputResolver(void* model, std::int64_t input_index)
  {
    auto* typed_model = static_cast<SmokeModel*>(model);
    if (typed_model == nullptr || input_index != 3)
    {
      return nullptr;
    }
    return &typed_model->work;
  }

  bool nearlyEqual(double lhs, double rhs)
  {
    constexpr double tolerance = 1.0e-12;
    return lhs > rhs ? lhs - rhs <= tolerance : rhs - lhs <= tolerance;
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
  if (source_vector == nullptr || destination_vector == nullptr || source_vector->data == nullptr || destination_vector->data == nullptr)
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

extern "C" void gridkitSmokeFwddiffGenLongYP(...) __asm__(
    "_ZN7GridKit6Enzyme6Sparse16__enzyme_fwddiffIvJiPNS_14PhasorDynamics12GenClassicalIdlEEiPKdPdiS8_iS8_iS9_S9_EEET_PvDpT0_");

extern "C" void gridkitSmokeFwddiffGenLongYP(...)
{
}

extern "C" void gridkitSmokeFwddiffGenLongYConst(...) __asm__(
    "_ZN7GridKit6Enzyme6Sparse16__enzyme_fwddiffIvJiPNS_14PhasorDynamics12GenClassicalIdlEEiPKdiS8_iS8_PdiS9_S9_EEET_PvDpT0_");

extern "C" void gridkitSmokeFwddiffGenLongYConst(...)
{
}

extern "C" void gridkitSmokeFwddiffGenLongY(...) __asm__(
    "_ZN7GridKit6Enzyme6Sparse16__enzyme_fwddiffIvJiPNS_14PhasorDynamics12GenClassicalIdlEEiPdiS7_S7_iS7_iS7_S7_EEET_PvDpT0_");

extern "C" void gridkitSmokeFwddiffGenLongY(...)
{
}

extern "C" void gridkitSmokeFwddiffGenSizeTYP(...) __asm__(
    "_ZN7GridKit6Enzyme6Sparse16__enzyme_fwddiffIvJiPNS_14PhasorDynamics12GenClassicalIdmEEiPKdPdiS8_iS8_iS9_S9_EEET_PvDpT0_");

extern "C" void gridkitSmokeFwddiffGenSizeTYP(...)
{
}

extern "C" void gridkitSmokeFwddiffGenSizeTYConst(...) __asm__(
    "_ZN7GridKit6Enzyme6Sparse16__enzyme_fwddiffIvJiPNS_14PhasorDynamics12GenClassicalIdmEEiPKdiS8_iS8_PdiS9_S9_EEET_PvDpT0_");

extern "C" void gridkitSmokeFwddiffGenSizeTYConst(...)
{
}

extern "C" void gridkitSmokeFwddiffGenSizeTY(...) __asm__(
    "_ZN7GridKit6Enzyme6Sparse16__enzyme_fwddiffIvJiPNS_14PhasorDynamics12GenClassicalIdmEEiPdiS7_S7_iS7_iS7_S7_EEET_PvDpT0_");

extern "C" void gridkitSmokeFwddiffGenSizeTY(...)
{
}

extern "C" void* gridkitSmokeTodenseDoublePointer(...) __asm__(
    "_ZN7GridKit6Enzyme6Sparse16__enzyme_todenseIPdEET_Pvz");

extern "C" void* gridkitSmokeTodenseDoublePointer(...)
{
  return nullptr;
}

extern "C" void gridkitSmokeCooLongCtorLong(void*, long, long, long) __asm__(
    "_ZN7GridKit13LinearAlgebra9CooMatrixIdlEC1Elll");

extern "C" void gridkitSmokeCooLongCtorLong(void*, long, long, long)
{
}

extern "C" void gridkitSmokeCooSizeTCtorSizeT(void*,
                                              unsigned long,
                                              unsigned long,
                                              unsigned long) __asm__("_ZN7GridKit13LinearAlgebra9CooMatrixIdmEC1Emmm");

extern "C" void gridkitSmokeCooSizeTCtorSizeT(void*,
                                              unsigned long,
                                              unsigned long,
                                              unsigned long)
{
}

extern "C" void gridkitSmokeCooLongDtor(void*) __asm__(
    "_ZN7GridKit13LinearAlgebra9CooMatrixIdlED1Ev");

extern "C" void gridkitSmokeCooLongDtor(void*)
{
}

extern "C" void gridkitSmokeCooSizeTDtor(void*) __asm__(
    "_ZN7GridKit13LinearAlgebra9CooMatrixIdmED1Ev");

extern "C" void gridkitSmokeCooSizeTDtor(void*)
{
}

extern "C" void gridkitSmokeCsrLongDtor(void*) __asm__(
    "_ZN7GridKit13LinearAlgebra9CsrMatrixIdlED1Ev");

extern "C" void gridkitSmokeCsrLongDtor(void*)
{
}

extern "C" void gridkitSmokeCsrSizeTDtor(void*) __asm__(
    "_ZN7GridKit13LinearAlgebra9CsrMatrixIdmED1Ev");

extern "C" void gridkitSmokeCsrSizeTDtor(void*)
{
}

extern "C" void gridkitSmokeCooLongSetDataPointers(void*,
                                                   long*,
                                                   long*,
                                                   double*,
                                                   int) __asm__("_ZN7GridKit13LinearAlgebra9CooMatrixIdlE15setDataPointersEPlS3_PdNS0_6memory11MemorySpaceE");

extern "C" void gridkitSmokeCooLongSetDataPointers(void*,
                                                   long*,
                                                   long*,
                                                   double*,
                                                   int)
{
}

extern "C" void gridkitSmokeCooSizeTSetDataPointers(void*,
                                                    unsigned long*,
                                                    unsigned long*,
                                                    double*,
                                                    int) __asm__("_ZN7GridKit13LinearAlgebra9CooMatrixIdmE15setDataPointersEPmS3_PdNS0_6memory11MemorySpaceE");

extern "C" void gridkitSmokeCooSizeTSetDataPointers(void*,
                                                    unsigned long*,
                                                    unsigned long*,
                                                    double*,
                                                    int)
{
}

extern "C" std::ostream& gridkitSmokeLoggerMisc() __asm__(
    "_ZN7GridKit9Utilities6Logger4miscEv");

extern "C" std::ostream& gridkitSmokeLoggerMisc()
{
  return std::cerr;
}

int main()
{
  using AnalysisManager::Sundials::Runtime::collectGeneratedIdaJvpInputs;
  using AnalysisManager::Sundials::Runtime::configureGeneratedIdaJvp;
  using AnalysisManager::Sundials::Runtime::hasGeneratedIdaJvpHostSplice;
  using AnalysisManager::Sundials::Runtime::teardownGeneratedIdaJvp;

  SmokeModel model{};
  model.work = 17.0;

  if (!check(hasGeneratedIdaJvpHostSplice(), "generated hook symbols missing"))
  {
    return 1;
  }

  std::vector<void*> inputs =
      collectGeneratedIdaJvpInputs(&model, &smokeInputResolver);
  if (!check(inputs.size() == 4, "generated input provider returned wrong size") || !check(inputs[0] == &model, "generated input provider missed model") || !check(inputs[1] == nullptr, "generated input provider changed slot 1") || !check(inputs[2] == nullptr, "generated input provider changed slot 2") || !check(inputs[3] == &model.work, "generated input provider missed host-resolved work slot"))
  {
    return 1;
  }

  double      yy_storage[3] = {1.0, 2.0, 3.0};
  SmokeVector yy{3, yy_storage};
  SmokeIdaMem ida_mem{};
  int         sunctx_token = 0;
  void*       generated_context{};

  int status = configureGeneratedIdaJvp(&ida_mem,
                                        &yy,
                                        &sunctx_token,
                                        &model,
                                        inputs.data(),
                                        static_cast<std::int64_t>(inputs.size()),
                                        &generated_context);
  if (!check(status == 0, "generated setup returned failure") || !check(generated_context != nullptr, "generated setup did not create context") || !check(ida_mem.user_data == generated_context, "generated setup did not install JVP context as IDA user data") || !check(ida_mem.linear_solver != nullptr, "generated setup did not create an iterative linear solver") || !check(ida_mem.matrix == nullptr, "generated setup should configure a matrix-free linear solver") || !check(ida_mem.jac_times != nullptr, "generated setup did not register a JacTimes callback") || !check(ida_mem.set_user_data_calls == 1, "generated setup called IDASetUserData unexpected number of times") || !check(ida_mem.set_linear_solver_calls == 1, "generated setup called IDASetLinearSolver unexpected number of times") || !check(ida_mem.set_jac_times_calls == 1, "generated setup called IDASetJacTimes unexpected number of times") || !check(sun_linear_solver_allocations == 1, "generated setup called SUNLinSol_SPGMR unexpected number of times"))
  {
    teardownGeneratedIdaJvp(&ida_mem);
    return 1;
  }

  auto* generated_linear_solver =
      static_cast<SmokeLinearSolver*>(ida_mem.linear_solver);
  if (!check(generated_linear_solver->template_vector == &yy,
             "generated linear solver used wrong template vector") ||
      !check(generated_linear_solver->pretype == 0,
             "generated linear solver used unexpected preconditioner type") ||
      !check(generated_linear_solver->maxl == yy.length,
             "generated linear solver did not use template vector length") ||
      !check(generated_linear_solver->sunctx == &sunctx_token,
             "generated linear solver used wrong SUNContext"))
  {
    teardownGeneratedIdaJvp(&ida_mem);
    return 1;
  }

  double      yp_storage[3]   = {4.0, 5.0, 6.0};
  double      rr_storage[3]   = {0.0, 0.0, 0.0};
  double      v_storage[3]    = {2.0, 4.0, 8.0};
  double      jv_storage[3]   = {1.0, 1.5, 2.0};
  double      tmp1_storage[3] = {-1.0, -1.0, -1.0};
  double      tmp2_storage[3] = {3.0, 5.0, 7.0};
  SmokeVector yp{3, yp_storage};
  SmokeVector rr{3, rr_storage};
  SmokeVector v{3, v_storage};
  SmokeVector jv{3, jv_storage};
  SmokeVector tmp1{3, tmp1_storage};
  SmokeVector tmp2{3, tmp2_storage};

  status = ida_mem.jac_times(0.125,
                             &yy,
                             &yp,
                             &rr,
                             &v,
                             &jv,
                             0.25,
                             generated_context,
                             &tmp1,
                             &tmp2);
  if (!check(status == 0, "generated JacTimes callback returned failure") || !check(nearlyEqual(tmp1_storage[0], 0.5), "JacTimes did not scale v[0]") || !check(nearlyEqual(tmp1_storage[1], 1.0), "JacTimes did not scale v[1]") || !check(nearlyEqual(tmp1_storage[2], 2.0), "JacTimes did not scale v[2]") || !check(nearlyEqual(jv_storage[0], 4.0), "JacTimes did not reach runtime accumulation for jv[0]") || !check(nearlyEqual(jv_storage[1], 6.5), "JacTimes did not reach runtime accumulation for jv[1]") || !check(nearlyEqual(jv_storage[2], 9.0), "JacTimes did not reach runtime accumulation for jv[2]"))
  {
    teardownGeneratedIdaJvp(&ida_mem);
    return 1;
  }

  teardownGeneratedIdaJvp(&ida_mem);
  if (!check(sun_linear_solver_frees == 1,
             "generated teardown did not release remembered linear solver"))
  {
    return 1;
  }

  std::cout << "generated runtime glue smoke: ok\n";
  return 0;
}
