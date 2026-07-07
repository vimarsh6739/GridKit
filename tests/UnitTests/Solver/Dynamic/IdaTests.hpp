#include <cmath>

#include <GridKit/Model/Evaluator.hpp>
#include <GridKit/Solver/Dynamic/Ida.hpp>
#include <GridKit/Solver/Dynamic/IdaJvpRuntime.hpp>
#include <GridKit/Testing/TestHelpers.hpp>
#include <GridKit/Testing/Testing.hpp>

using AnalysisManager::Sundials::Ida;

namespace GridKit
{
  namespace Model
  {
    template <class ScalarT, typename IdxT>
    class NullEvaluator : public Model::Evaluator<ScalarT, IdxT>
    {
    public:
      using RealT = typename Model::Evaluator<ScalarT, IdxT>::RealT;

      NullEvaluator()
      {
      }

      int allocate() override
      {
        return 0;
      }

      int initialize() override
      {
        y_  = {0};
        yp_ = {0};

        tag_     = {false};
        abs_tol_ = {0};

        f_ = {0};
        g_ = {0};
        return 0;
      }

      IdxT size() override
      {
        return 1;
      }

      IdxT nnz() override
      {
        return 0;
      }

      bool hasJacobian() override
      {
        return false;
      }

      IdxT sizeQuadrature() override
      {
        return 0;
      }

      IdxT sizeParams() override
      {
        return 0;
      }

      int tagDifferentiable() override
      {
        return 0;
      }

      int setAbsoluteTolerance(RealT rel_tol) override
      {
        std::fill(abs_tol_.begin(), abs_tol_.end(), rel_tol);
        return 0;
      }

      int evaluateResidual() override
      {
        f_ = y_;
        return 0;
      }

      int evaluateJacobian() override
      {
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

      void updateTime([[maybe_unused]] RealT t, [[maybe_unused]] RealT a) override
      {
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

      std::vector<ScalarT>& absoluteTolerance() override
      {
        return abs_tol_;
      }

      const std::vector<ScalarT>& absoluteTolerance() const override
      {
        return abs_tol_;
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

      GridKit::LinearAlgebra::CsrMatrix<RealT, IdxT>* getCsrJacobian() const override
      {
        return csr_jac_;
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

      IdxT getIDcomponent()
      {
        return 0;
      }

    protected:
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

      GridKit::LinearAlgebra::CsrMatrix<RealT, IdxT>* csr_jac_;

      std::vector<ScalarT> param_;
      std::vector<ScalarT> param_up_;
      std::vector<ScalarT> param_lo_;
    };

    template <class ScalarT, typename IdxT>
    class AlgebraicErrorControlEvaluator : public NullEvaluator<ScalarT, IdxT>
    {
    public:
      using RealT = typename NullEvaluator<ScalarT, IdxT>::RealT;

      int initialize() override
      {
        this->y_       = {0, 0};
        this->yp_      = {0, 0};
        this->tag_     = {true, false};
        this->abs_tol_ = {0, 0};
        this->f_       = {0, 0};
        this->g_       = {0};
        t_             = 0;
        return 0;
      }

      IdxT size() override
      {
        return 2;
      }

      int evaluateResidual() override
      {
        static constexpr RealT OMEGA = 100.0;
        this->f_[0]                  = this->yp_[0];
        this->f_[1]                  = this->y_[1] - std::sin(OMEGA * t_);
        return 0;
      }

      void updateTime(RealT t, [[maybe_unused]] RealT a) override
      {
        t_ = t;
      }

    private:
      RealT t_{};
    };
  } // namespace Model

  namespace Testing
  {
    template <class ScalarT, typename IdxT>
    class IdaTests
    {
    public:
      TestOutcome callback()
      {
        const unsigned n_steps = 100;
        TestStatus     success = true;

        Model::NullEvaluator<ScalarT, IdxT> model;

        Ida<double, size_t> ida(&model);
        ida.configureSimulation();

        unsigned observed_steps = 0;
        auto     output_cb      = [&]([[maybe_unused]] double t)
        {
          observed_steps++;
        };

        ida.initializeSimulation(0.0, false);
        ida.runSimulation(1.0, n_steps, output_cb);

        success *= (observed_steps == n_steps);

        return success.report(__func__);
      }

      TestOutcome fixedStep()
      {
        const unsigned n_steps = 32;
        TestStatus     success = true;

        Model::NullEvaluator<ScalarT, IdxT> model;

        Ida<double, size_t> ida(&model);
        ida.setFixedStep(1.0 / n_steps);
        ida.setTolerance(1.0e-6);
        ida.configureSimulation();

        ida.initializeSimulation(0.0, false);
        ida.runSimulation(1.0);
        auto stats = ida.getStats();

        success *= (stats.num_steps_ == n_steps);

        return success.report(__func__);
      }

      TestOutcome suppressAlgebraicErrors()
      {
        TestStatus success = true;

        const auto countSteps = [](bool suppress_alg)
        {
          Model::AlgebraicErrorControlEvaluator<ScalarT, IdxT> model;

          Ida<ScalarT, IdxT> ida(&model);
          ida.setSuppressAlgebraicErrors(suppress_alg);
          ida.setTolerance(1.0e-6);
          ida.setMaxSteps(10000);
          ida.configureSimulation();

          ida.initializeSimulation(0.0, false);
          ida.runSimulation(1.0);

          return ida.getStats().num_steps_;
        };

        const auto unsuppressed_steps = countSteps(false);
        const auto suppressed_steps   = countSteps(true);

        success *= (suppressed_steps < unsuppressed_steps);

        return success.report(__func__);
      }

      TestOutcome compilerGeneratedJvpUserData()
      {
        TestStatus success = true;

        double model_token = 42.0;
        double wb[]        = {1.25, -0.5};
        void*  inputs[]    = {&model_token, nullptr, nullptr, wb};
        double jv[]        = {1.0, 2.0, 3.0};
        double tmp[]       = {0.5, 1.5, -2.0};

        AnalysisManager::Sundials::Runtime::IdaJvpUserData context{
          &model_token,
          inputs,
          4,
          3,
        };
        __enzymexla_sundials_ida_register_jvp_context(&context);

        success *= (AnalysisManager::Sundials::Runtime::unwrapIdaUserDataModel(&context) == &model_token);
        success *= (AnalysisManager::Sundials::Runtime::unwrapIdaUserDataModel(&model_token) == &model_token);
        success *= (__enzymexla_sundials_ida_context_input(&context, 0) == &model_token);
        success *= (__enzymexla_sundials_ida_context_input(&context, 3) == wb);
        success *= (__enzymexla_sundials_ida_context_input(&context, 4) == nullptr);
        success *= (__enzymexla_sundials_ida_context_input(&model_token, 0) == &model_token);
        success *= (__enzymexla_sundials_ida_context_input(&model_token, 3) == nullptr);

        const int status = __enzymexla_sundials_ida_accumulate_raw_jvp(&context, jv, tmp);
        success *= (status == 0);
        success *= isEqual(jv[0], 1.5);
        success *= isEqual(jv[1], 3.5);
        success *= isEqual(jv[2], 1.0);
        success *= (__enzymexla_sundials_ida_accumulate_raw_jvp(&model_token, jv, tmp) != 0);

        __enzymexla_sundials_ida_unregister_jvp_context(&context);

        void* generated_context =
          __enzymexla_sundials_ida_create_jvp_context(&model_token, inputs, 4, 3);
        success *= (generated_context != nullptr);
        __enzymexla_sundials_ida_register_jvp_context(generated_context);
        inputs[3] = nullptr;

        double generated_jv[]  = {4.0, 5.0, 6.0};
        double generated_tmp[] = {-1.0, 2.0, 0.25};
        success *= (AnalysisManager::Sundials::Runtime::unwrapIdaUserDataModel(generated_context) == &model_token);
        success *= (__enzymexla_sundials_ida_context_input(generated_context, 3) == wb);
        success *= (__enzymexla_sundials_ida_accumulate_raw_jvp(generated_context,
                                                                 generated_jv,
                                                                 generated_tmp) == 0);
        success *= isEqual(generated_jv[0], 3.0);
        success *= isEqual(generated_jv[1], 7.0);
        success *= isEqual(generated_jv[2], 6.25);

        double ida_mem_token = 0.0;
        __enzymexla_sundials_ida_remember_jvp_context(&ida_mem_token,
                                                       generated_context);
        __enzymexla_sundials_ida_destroy_remembered_jvp_context(&ida_mem_token);
        success *= (!AnalysisManager::Sundials::Runtime::isIdaJvpUserData(generated_context));
        __enzymexla_sundials_ida_destroy_remembered_jvp_context(&ida_mem_token);

        void* direct_destroy_context =
          __enzymexla_sundials_ida_create_jvp_context(&model_token, inputs, 4, 3);
        __enzymexla_sundials_ida_register_jvp_context(direct_destroy_context);
        double direct_destroy_ida_mem_token = 0.0;
        __enzymexla_sundials_ida_remember_jvp_context(&direct_destroy_ida_mem_token,
                                                       direct_destroy_context);
        __enzymexla_sundials_ida_destroy_jvp_context(direct_destroy_context);
        success *= (!AnalysisManager::Sundials::Runtime::isIdaJvpUserData(direct_destroy_context));
        __enzymexla_sundials_ida_destroy_remembered_jvp_context(
          &direct_destroy_ida_mem_token);
        success *= (__enzymexla_sundials_ida_create_jvp_context(&model_token, inputs, -1, 3) == nullptr);

        double linear_solver_owner = 0.0;
        double linear_solver_token = 0.0;
        AnalysisManager::Sundials::Runtime::rememberIdaGeneratedLinearSolver(
          &linear_solver_owner,
          &linear_solver_token);
        success *= (AnalysisManager::Sundials::Runtime::takeRememberedIdaGeneratedLinearSolver(
                      &linear_solver_owner) == &linear_solver_token);
        success *= (AnalysisManager::Sundials::Runtime::takeRememberedIdaGeneratedLinearSolver(
                      &linear_solver_owner) == nullptr);
        __enzymexla_sundials_ida_destroy_remembered_linear_solver(
          &linear_solver_owner);

        return success.report(__func__);
      }
    };
  } // namespace Testing
} // namespace GridKit
