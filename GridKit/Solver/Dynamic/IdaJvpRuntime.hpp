#pragma once

#include <cstddef>
#include <cstdint>

namespace AnalysisManager
{
  namespace Sundials
  {
    namespace Runtime
    {
      /**
       * @brief User-data object for compiler-generated IDA Jacobian-action callbacks.
       *
       * Existing GridKit IDA callbacks historically receive the model pointer
       * directly as SUNDIALS user data. Compiler-generated JVP callbacks need a
       * little more context: the original model pointer, non-N_Vector residual
       * inputs, and the output size used to accumulate dF/dy*v and
       * dF/dyp*(cj*v). The runtime registration keeps this object discoverable
       * without changing the legacy model-as-user-data ABI.
       */
      struct IdaJvpUserData
      {
        void*        model{};
        void**       inputs{};
        std::size_t  input_count{};
        std::size_t  output_size{};
      };

      void registerIdaJvpUserData(IdaJvpUserData* user_data);
      void unregisterIdaJvpUserData(IdaJvpUserData* user_data);
      bool isIdaJvpUserData(const void* user_data);
      void* unwrapIdaUserDataModel(void* user_data);
    } // namespace Runtime
  } // namespace Sundials
} // namespace AnalysisManager

extern "C" void* __enzymexla_sundials_ida_context_input(void* user_data,
                                                         std::int64_t input_index);

extern "C" int __enzymexla_sundials_ida_accumulate_raw_jvp(void* user_data,
                                                            void* jv,
                                                            void* tmp);

extern "C" void* __enzymexla_sundials_ida_create_jvp_context(void* model,
                                                              void** inputs,
                                                              std::int64_t input_count,
                                                              std::int64_t output_size);

extern "C" void __enzymexla_sundials_ida_destroy_jvp_context(void* user_data);

extern "C" void __enzymexla_sundials_ida_register_jvp_context(void* user_data);

extern "C" void __enzymexla_sundials_ida_unregister_jvp_context(void* user_data);
