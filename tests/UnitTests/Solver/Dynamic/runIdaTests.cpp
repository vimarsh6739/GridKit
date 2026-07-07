#include "IdaTests.hpp"

#include <array>
#include <cstdint>
#include <vector>

namespace
{
  struct GeneratedIdaHookTestState
  {
    bool                 enabled{};
    void*                expected_model{};
    void*                work_buffer{};
    void*                context_token{};
    void*                setup_ida_mem{};
    void*                setup_yy_template{};
    void*                setup_sunctx{};
    void*                setup_model{};
    std::int64_t         setup_input_count{};
    std::array<void*, 4> setup_inputs{};
    int                  setup_calls{};
    int                  teardown_calls{};

    void reset()
    {
      enabled           = false;
      expected_model    = nullptr;
      work_buffer       = nullptr;
      context_token     = this;
      setup_ida_mem     = nullptr;
      setup_yy_template = nullptr;
      setup_sunctx      = nullptr;
      setup_model       = nullptr;
      setup_input_count = 0;
      setup_inputs.fill(nullptr);
      setup_calls    = 0;
      teardown_calls = 0;
    }
  };

  GeneratedIdaHookTestState generated_ida_hook_test_state;

  GridKit::Testing::TestOutcome compilerGeneratedIdaHostSplice()
  {
    using AnalysisManager::Sundials::Ida;
    using AnalysisManager::Sundials::Runtime::collectGeneratedIdaJvpInputs;
    using AnalysisManager::Sundials::Runtime::hasGeneratedIdaJvpHostSplice;

    GridKit::Testing::TestStatus success = true;

    GridKit::Model::NullEvaluator<double, size_t> model;
    double                                        work_buffer = 0.0;

    generated_ida_hook_test_state.reset();
    generated_ida_hook_test_state.enabled        = true;
    generated_ida_hook_test_state.expected_model = &model;
    generated_ida_hook_test_state.work_buffer    = &work_buffer;

    success *= hasGeneratedIdaJvpHostSplice();
    std::vector<void*> inputs = collectGeneratedIdaJvpInputs(&model);
    success *= (inputs.size() == 4);
    success *= (inputs[0] == &model);
    success *= (inputs[3] == &work_buffer);
    success *= (AnalysisManager::Sundials::Runtime::resolveGeneratedIdaJvpInput(
                  &model,
                  0) == &model);
    success *= (AnalysisManager::Sundials::Runtime::resolveGeneratedIdaJvpInput(
                  &model,
                  3) == &work_buffer);

    {
      Ida<double, size_t> ida(&model);
      success *= (ida.configureSimulation() == 0);
      success *= (generated_ida_hook_test_state.setup_calls == 1);
      success *= (generated_ida_hook_test_state.setup_ida_mem != nullptr);
      success *= (generated_ida_hook_test_state.setup_yy_template != nullptr);
      success *= (generated_ida_hook_test_state.setup_sunctx != nullptr);
      success *= (generated_ida_hook_test_state.setup_model == &model);
      success *= (generated_ida_hook_test_state.setup_input_count == 4);
      success *= (generated_ida_hook_test_state.setup_inputs[0] == &model);
      success *= (generated_ida_hook_test_state.setup_inputs[3] == &work_buffer);
    }

    success *= (generated_ida_hook_test_state.teardown_calls == 1);
    generated_ida_hook_test_state.reset();

    return success.report(__func__);
  }
} // namespace

extern "C" int __enzymexla_sundials_ida_setup_generated_jactimes(void* ida_mem,
                                                                  void* yy_template,
                                                                  void* sunctx,
                                                                  void* model,
                                                                  void** inputs,
                                                                  std::int64_t input_count,
                                                                  void** context_out)
{
  auto& state = generated_ida_hook_test_state;
  ++state.setup_calls;
  state.setup_ida_mem     = ida_mem;
  state.setup_yy_template = yy_template;
  state.setup_sunctx      = sunctx;
  state.setup_model       = model;
  state.setup_input_count = input_count;
  state.setup_inputs.fill(nullptr);

  if (!state.enabled || model != state.expected_model || input_count != 4 ||
      inputs == nullptr || context_out == nullptr)
  {
    return 1;
  }

  for (std::size_t index = 0; index < state.setup_inputs.size(); ++index)
  {
    state.setup_inputs[index] = inputs[index];
  }
  *context_out = state.context_token;
  return 0;
}

extern "C" void __enzymexla_sundials_ida_teardown_generated_jactimes(void* ida_mem)
{
  auto& state = generated_ida_hook_test_state;
  if (state.enabled && ida_mem == state.setup_ida_mem)
  {
    ++state.teardown_calls;
  }
}

extern "C" std::int64_t __enzymexla_sundials_ida_fill_generated_jvp_inputs(void* model,
                                                                             void** inputs,
                                                                             std::int64_t input_capacity)
{
  auto& state = generated_ida_hook_test_state;
  if (!state.enabled || model != state.expected_model)
  {
    return 0;
  }

  constexpr std::int64_t input_count = 4;
  if (inputs == nullptr)
  {
    return input_count;
  }
  if (input_capacity < input_count)
  {
    return -1;
  }

  inputs[0] = model;
  inputs[1] = nullptr;
  inputs[2] = nullptr;
  inputs[3] = state.work_buffer;
  return input_count;
}

extern "C" void* __enzymexla_sundials_ida_resolve_generated_jvp_input_from_host(void* model,
                                                                                  std::int64_t input_index)
{
  auto& state = generated_ida_hook_test_state;
  if (!state.enabled || model != state.expected_model || input_index != 3)
  {
    return nullptr;
  }

  return state.work_buffer;
}

int main()
{
  using namespace GridKit;
  using namespace GridKit::Testing;

  GridKit::Testing::TestingResults           result;
  GridKit::Testing::IdaTests<double, size_t> test;

  result += test.callback();
  result += test.fixedStep();
  result += test.suppressAlgebraicErrors();
  result += test.compilerGeneratedJvpUserData();
  result += compilerGeneratedIdaHostSplice();

  return result.summary();
}
