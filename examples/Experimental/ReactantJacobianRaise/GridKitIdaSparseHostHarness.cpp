/**
 * @file GridKitIdaSparseHostHarness.cpp
 *
 * Export-only harness for raising GridKit's existing SUNDIALS IDA sparse
 * solver setup into LLVM IR and Reactant/MLIR. SUNDIALS is intentionally kept
 * as an external boundary through declaration-only shim headers used by the
 * export script.
 */

#include <algorithm>
#include <cstddef>
#include <vector>

#include <GridKit/LinearAlgebra/SparseMatrix/CsrMatrix.hpp>
#include <GridKit/Model/Evaluator.hpp>

#include <GridKit/Solver/Dynamic/Ida.cpp>

namespace
{
  template <class ScalarT, typename IdxT>
  class SparseOneStateEvaluator final : public GridKit::Model::Evaluator<ScalarT, IdxT>
  {
  public:
    using RealT      = typename GridKit::ScalarTraits<ScalarT>::RealT;
    using CsrMatrixT = GridKit::LinearAlgebra::CsrMatrix<RealT, IdxT>;

    SparseOneStateEvaluator()
      : jac_(1, 1, 1)
    {
    }

    int allocate() override
    {
      jac_.allocateMatrixData(GridKit::LinearAlgebra::memory::HOST);
      IdxT*  row_ptrs = jac_.getRowData();
      IdxT*  cols     = jac_.getColData();
      RealT* vals     = jac_.getValues();
      row_ptrs[0]     = 0;
      row_ptrs[1]     = 1;
      cols[0]         = 0;
      vals[0]         = 1.0;
      jac_.setUpdated(GridKit::LinearAlgebra::memory::HOST);
      return 0;
    }

    int initialize() override
    {
      y_       = {0.0};
      yp_      = {0.0};
      tag_     = {true};
      abs_tol_ = {0.0};
      f_       = {0.0};
      g_       = {};
      yB_      = {0.0};
      ypB_     = {0.0};
      fB_      = {0.0};
      gB_      = {};
      param_   = {};
      param_up_ = {};
      param_lo_ = {};
      return 0;
    }

    int tagDifferentiable() override
    {
      tag_ = {true};
      return 0;
    }

    int setAbsoluteTolerance(RealT rel_tol) override
    {
      abs_tol_ = {rel_tol};
      return 0;
    }

    int evaluateResidual() override
    {
      f_[0] = yp_[0] + y_[0] - t_;
      return 0;
    }

    int evaluateJacobian() override
    {
      RealT* vals = jac_.getValues();
      vals[0]     = 1.0 + cj_;
      jac_.setUpdated(GridKit::LinearAlgebra::memory::HOST);
      return 0;
    }

    int evaluateIntegrand() override
    {
      return 0;
    }

    int initializeAdjoint() override
    {
      return 0;
    }

    int evaluateAdjointResidual() override
    {
      return 0;
    }

    int evaluateAdjointIntegrand() override
    {
      return 0;
    }

    IdxT size() override
    {
      return 1;
    }

    IdxT nnz() override
    {
      return 1;
    }

    CsrMatrixT* getCsrJacobian() const override
    {
      return const_cast<CsrMatrixT*>(&jac_);
    }

    bool hasJacobian() override
    {
      return true;
    }

    IdxT sizeQuadrature() override
    {
      return 0;
    }

    IdxT sizeParams() override
    {
      return 0;
    }

    void updateTime(RealT t, RealT a) override
    {
      t_  = t;
      cj_ = a;
    }

    std::vector<ScalarT>& absoluteTolerance() override
    {
      return abs_tol_;
    }

    const std::vector<ScalarT>& absoluteTolerance() const override
    {
      return abs_tol_;
    }

    std::vector<ScalarT>& y() override
    {
      return y_;
    }

    const std::vector<ScalarT>& y() const override
    {
      return y_;
    }

    std::vector<ScalarT>& yp() override
    {
      return yp_;
    }

    const std::vector<ScalarT>& yp() const override
    {
      return yp_;
    }

    std::vector<bool>& tag() override
    {
      return tag_;
    }

    const std::vector<bool>& tag() const override
    {
      return tag_;
    }

    std::vector<ScalarT>& yB() override
    {
      return yB_;
    }

    const std::vector<ScalarT>& yB() const override
    {
      return yB_;
    }

    std::vector<ScalarT>& ypB() override
    {
      return ypB_;
    }

    const std::vector<ScalarT>& ypB() const override
    {
      return ypB_;
    }

    std::vector<ScalarT>& param() override
    {
      return param_;
    }

    const std::vector<ScalarT>& param() const override
    {
      return param_;
    }

    std::vector<ScalarT>& param_up() override
    {
      return param_up_;
    }

    const std::vector<ScalarT>& param_up() const override
    {
      return param_up_;
    }

    std::vector<ScalarT>& param_lo() override
    {
      return param_lo_;
    }

    const std::vector<ScalarT>& param_lo() const override
    {
      return param_lo_;
    }

    std::vector<ScalarT>& getResidual() override
    {
      return f_;
    }

    const std::vector<ScalarT>& getResidual() const override
    {
      return f_;
    }

    std::vector<ScalarT>& getIntegrand() override
    {
      return g_;
    }

    const std::vector<ScalarT>& getIntegrand() const override
    {
      return g_;
    }

    std::vector<ScalarT>& getAdjointResidual() override
    {
      return fB_;
    }

    const std::vector<ScalarT>& getAdjointResidual() const override
    {
      return fB_;
    }

    std::vector<ScalarT>& getAdjointIntegrand() override
    {
      return gB_;
    }

    const std::vector<ScalarT>& getAdjointIntegrand() const override
    {
      return gB_;
    }

  private:
    CsrMatrixT jac_;

    RealT t_{};
    RealT cj_{};

    std::vector<ScalarT> y_;
    std::vector<ScalarT> yp_;
    std::vector<bool>    tag_;
    std::vector<ScalarT> abs_tol_;
    std::vector<ScalarT> f_;
    std::vector<ScalarT> g_;

    std::vector<ScalarT> yB_;
    std::vector<ScalarT> ypB_;
    std::vector<ScalarT> fB_;
    std::vector<ScalarT> gB_;

    std::vector<ScalarT> param_;
    std::vector<ScalarT> param_up_;
    std::vector<ScalarT> param_lo_;
  };
} // namespace

extern "C" std::size_t gridkit_ida_existing_sparse_solver_configuration()
{
  using ScalarT   = double;
  using IdxT      = std::size_t;
  using ModelT    = SparseOneStateEvaluator<ScalarT, IdxT>;
  using IdaSolver = AnalysisManager::Sundials::Ida<ScalarT, IdxT>;

  ModelT model;
  model.allocate();

  IdaSolver ida(&model);
  ida.configureSimulation();

  return static_cast<std::size_t>(model.nnz());
}

