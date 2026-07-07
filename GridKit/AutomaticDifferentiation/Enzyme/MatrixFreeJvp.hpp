/**
 * @file MatrixFreeJvp.hpp
 *
 * @brief Experimental Enzyme forward-mode Jacobian-vector products.
 */

#pragma once

#include <algorithm>
#include <vector>

#include <GridKit/AutomaticDifferentiation/Enzyme/EnzymeDefinitions.hpp>
#include <GridKit/AutomaticDifferentiation/Enzyme/ModelWrappers.hpp>

namespace GridKit
{
  namespace Enzyme
  {
    namespace MatrixFree
    {
      /**
       * @brief Dense matrix-free residual JVP for existing phasor-dynamics residual wrappers.
       *
       * @details This computes
       *
       *     d residual / d y  * y_seed
       *   + d residual / d yp * yp_seed
       *   + d residual / d wb * wb_seed
       *
       * in a single Enzyme forward-mode call. For an IDA matrix-free callback,
       * callers should pass yp_seed = cj * y_seed for variables represented by
       * IDA's solution vector. This helper intentionally does not allocate or
       * materialize sparse Jacobian storage.
       *
       * TODO: lift this component-level helper into a system-level operator that
       * scatters/gathers global SUNDIALS N_Vector storage without exposing GridKit
       * component internals.
       */
      template <typename ModelT, Sparse::MemberFunctions function>
      struct ResidualJvp
      {
        using ScalarT = typename ModelT::ScalarT;

        static void eval(ModelT*        model,
                         const size_t   n_res,
                         ScalarT*       y,
                         ScalarT*       y_seed,
                         ScalarT*       yp,
                         ScalarT*       yp_seed,
                         ScalarT*       wb,
                         ScalarT*       wb_seed,
                         ScalarT*       residual_seed)
        {
          std::vector<ScalarT> residual_primal(n_res);
          std::fill(residual_seed, residual_seed + n_res, ScalarT{});

          Sparse::__enzyme_fwddiff<void>((void*) Sparse::ModelWrapper<ModelT, function>::eval,
                                         enzyme_const,
                                         model,
                                         enzyme_dup,
                                         y,
                                         y_seed,
                                         enzyme_dup,
                                         yp,
                                         yp_seed,
                                         enzyme_dup,
                                         wb,
                                         wb_seed,
                                         enzyme_dupnoneed,
                                         residual_primal.data(),
                                         residual_seed);
        }

        static void eval(ModelT*        model,
                         const size_t   n_res,
                         ScalarT*       y,
                         ScalarT*       y_seed,
                         ScalarT*       yp,
                         ScalarT*       yp_seed,
                         ScalarT*       wb,
                         ScalarT*       wb_seed,
                         ScalarT*       ws,
                         ScalarT*       ws_seed,
                         ScalarT*       residual_seed)
        {
          std::vector<ScalarT> residual_primal(n_res);
          std::fill(residual_seed, residual_seed + n_res, ScalarT{});

          Sparse::__enzyme_fwddiff<void>((void*) Sparse::ModelWrapper<ModelT, function>::eval,
                                         enzyme_const,
                                         model,
                                         enzyme_dup,
                                         y,
                                         y_seed,
                                         enzyme_dup,
                                         yp,
                                         yp_seed,
                                         enzyme_dup,
                                         wb,
                                         wb_seed,
                                         enzyme_dup,
                                         ws,
                                         ws_seed,
                                         enzyme_dupnoneed,
                                         residual_primal.data(),
                                         residual_seed);
        }
      };
    } // namespace MatrixFree
  } // namespace Enzyme
} // namespace GridKit
