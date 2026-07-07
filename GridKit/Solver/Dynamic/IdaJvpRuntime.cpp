#include "IdaJvpRuntime.hpp"

#include <mutex>
#include <new>
#include <unordered_map>
#include <unordered_set>

namespace AnalysisManager
{
  namespace Sundials
  {
    namespace Runtime
    {
      namespace
      {
        std::mutex& userDataRegistryMutex()
        {
          static std::mutex registry_mutex;
          return registry_mutex;
        }

        std::unordered_set<const void*>& userDataRegistry()
        {
          static std::unordered_set<const void*> registry;
          return registry;
        }

        std::mutex& ownerRegistryMutex()
        {
          static std::mutex registry_mutex;
          return registry_mutex;
        }

        std::unordered_map<const void*, IdaJvpUserData*>& ownerRegistry()
        {
          static std::unordered_map<const void*, IdaJvpUserData*> registry;
          return registry;
        }

      } // namespace

      void registerIdaJvpUserData(IdaJvpUserData* user_data)
      {
        if (user_data == nullptr)
        {
          return;
        }

        std::lock_guard<std::mutex> lock(userDataRegistryMutex());
        userDataRegistry().insert(user_data);
      }

      void unregisterIdaJvpUserData(IdaJvpUserData* user_data)
      {
        if (user_data == nullptr)
        {
          return;
        }

        std::lock_guard<std::mutex> lock(userDataRegistryMutex());
        userDataRegistry().erase(user_data);
      }

      void destroyGeneratedIdaJvpUserData(IdaJvpUserData* user_data)
      {
        if (user_data == nullptr)
        {
          return;
        }

        {
          std::lock_guard<std::mutex> lock(ownerRegistryMutex());
          for (auto iter = ownerRegistry().begin(); iter != ownerRegistry().end();)
          {
            if (iter->second == user_data)
            {
              iter = ownerRegistry().erase(iter);
            }
            else
            {
              ++iter;
            }
          }
        }

        unregisterIdaJvpUserData(user_data);
        delete user_data;
      }

      bool isIdaJvpUserData(const void* user_data)
      {
        std::lock_guard<std::mutex> lock(userDataRegistryMutex());
        return userDataRegistry().contains(user_data);
      }

      void* unwrapIdaUserDataModel(void* user_data)
      {
        if (!isIdaJvpUserData(user_data))
        {
          return user_data;
        }

        auto* context = static_cast<IdaJvpUserData*>(user_data);
        return context->model;
      }

      void rememberIdaJvpUserData(void* owner, IdaJvpUserData* user_data)
      {
        if (owner == nullptr || user_data == nullptr)
        {
          return;
        }

        IdaJvpUserData* replaced = nullptr;
        {
          std::lock_guard<std::mutex> lock(ownerRegistryMutex());
          auto& slot = ownerRegistry()[owner];
          if (slot == user_data)
          {
            return;
          }
          replaced = slot;
          slot     = user_data;
        }

        destroyGeneratedIdaJvpUserData(replaced);
      }

      IdaJvpUserData* takeRememberedIdaJvpUserData(void* owner)
      {
        if (owner == nullptr)
        {
          return nullptr;
        }

        std::lock_guard<std::mutex> lock(ownerRegistryMutex());
        auto                        found = ownerRegistry().find(owner);
        if (found == ownerRegistry().end())
        {
          return nullptr;
        }

        IdaJvpUserData* user_data = found->second;
        ownerRegistry().erase(found);
        return user_data;
      }
    } // namespace Runtime
  } // namespace Sundials
} // namespace AnalysisManager

extern "C" void* __enzymexla_sundials_ida_context_input(void* user_data,
                                                         std::int64_t input_index)
{
  using AnalysisManager::Sundials::Runtime::IdaJvpUserData;
  using AnalysisManager::Sundials::Runtime::isIdaJvpUserData;

  if (input_index < 0)
  {
    return nullptr;
  }

  if (!isIdaJvpUserData(user_data))
  {
    return input_index == 0 ? user_data : nullptr;
  }

  auto* context = static_cast<IdaJvpUserData*>(user_data);
  if (input_index == 0 && context->model != nullptr)
  {
    return context->model;
  }

  const auto index = static_cast<std::size_t>(input_index);
  if (context->inputs == nullptr || index >= context->input_count)
  {
    return nullptr;
  }

  return context->inputs[index];
}

extern "C" int __enzymexla_sundials_ida_accumulate_raw_jvp(void* user_data,
                                                            void* jv,
                                                            void* tmp)
{
  using AnalysisManager::Sundials::Runtime::IdaJvpUserData;
  using AnalysisManager::Sundials::Runtime::isIdaJvpUserData;

  if (!isIdaJvpUserData(user_data) || jv == nullptr || tmp == nullptr)
  {
    return 1;
  }

  auto* context = static_cast<IdaJvpUserData*>(user_data);
  if (context->output_size == 0)
  {
    return 1;
  }

  auto*       jv_values  = static_cast<double*>(jv);
  const auto* tmp_values = static_cast<const double*>(tmp);
  for (std::size_t index = 0; index < context->output_size; ++index)
  {
    jv_values[index] += tmp_values[index];
  }

  return 0;
}

extern "C" void* __enzymexla_sundials_ida_create_jvp_context(void* model,
                                                              void** inputs,
                                                              std::int64_t input_count,
                                                              std::int64_t output_size)
{
  using AnalysisManager::Sundials::Runtime::IdaJvpUserData;

  if (input_count < 0 || output_size < 0)
  {
    return nullptr;
  }

  auto* context = new (std::nothrow) IdaJvpUserData{};
  if (context == nullptr)
  {
    return nullptr;
  }

  context->model       = model;
  context->input_count = static_cast<std::size_t>(input_count);
  context->output_size = static_cast<std::size_t>(output_size);

  try
  {
    context->owned_inputs.resize(context->input_count, nullptr);
    for (std::size_t index = 0; index < context->input_count; ++index)
    {
      context->owned_inputs[index] =
        inputs == nullptr ? nullptr : inputs[index];
    }
  }
  catch (...)
  {
    delete context;
    return nullptr;
  }

  context->inputs =
    context->owned_inputs.empty() ? nullptr : context->owned_inputs.data();
  return context;
}

extern "C" void __enzymexla_sundials_ida_destroy_jvp_context(void* user_data)
{
  using AnalysisManager::Sundials::Runtime::destroyGeneratedIdaJvpUserData;
  using AnalysisManager::Sundials::Runtime::IdaJvpUserData;

  destroyGeneratedIdaJvpUserData(static_cast<IdaJvpUserData*>(user_data));
}

extern "C" void __enzymexla_sundials_ida_remember_jvp_context(void* ida_mem,
                                                               void* user_data)
{
  using AnalysisManager::Sundials::Runtime::IdaJvpUserData;
  using AnalysisManager::Sundials::Runtime::rememberIdaJvpUserData;

  rememberIdaJvpUserData(ida_mem, static_cast<IdaJvpUserData*>(user_data));
}

extern "C" void __enzymexla_sundials_ida_destroy_remembered_jvp_context(void* ida_mem)
{
  using AnalysisManager::Sundials::Runtime::destroyGeneratedIdaJvpUserData;
  using AnalysisManager::Sundials::Runtime::takeRememberedIdaJvpUserData;

  destroyGeneratedIdaJvpUserData(takeRememberedIdaJvpUserData(ida_mem));
}

extern "C" void __enzymexla_sundials_ida_register_jvp_context(void* user_data)
{
  using AnalysisManager::Sundials::Runtime::IdaJvpUserData;
  using AnalysisManager::Sundials::Runtime::registerIdaJvpUserData;

  registerIdaJvpUserData(static_cast<IdaJvpUserData*>(user_data));
}

extern "C" void __enzymexla_sundials_ida_unregister_jvp_context(void* user_data)
{
  using AnalysisManager::Sundials::Runtime::IdaJvpUserData;
  using AnalysisManager::Sundials::Runtime::unregisterIdaJvpUserData;

  unregisterIdaJvpUserData(static_cast<IdaJvpUserData*>(user_data));
}
