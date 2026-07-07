#pragma once

#include <idas/idas.h>
#include <sunlinsol/sunlinsol_dense.h>
#include <sunmatrix/sunmatrix_sparse.h>

extern "C" int IDASetLinearSolver(void*, SUNLinearSolver, SUNMatrix);
extern "C" int IDASetLinearSolverB(void*, int, SUNLinearSolver, SUNMatrix);
extern "C" int IDASetJacFn(void*, ...);
extern "C" int IDASetJacTimes(void*, ...);
extern "C" int IDASetPreconditioner(void*, ...);

