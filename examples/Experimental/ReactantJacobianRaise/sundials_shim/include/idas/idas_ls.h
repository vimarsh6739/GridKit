#pragma once

#include <idas/idas.h>
#include <sunlinsol/sunlinsol_dense.h>
#include <sunmatrix/sunmatrix_sparse.h>

extern "C" int IDASetLinearSolver(void*, SUNLinearSolver, SUNMatrix);
extern "C" int IDASetLinearSolverB(void*, int, SUNLinearSolver, SUNMatrix);
extern "C" int IDASetJacFn(void*, ...);
extern "C" int IDASetJacTimes(void*, ...);
extern "C" int IDASetPreconditioner(void*, ...);
extern "C" int IDAGetNumJacEvals(void*, long int*);
extern "C" int IDAGetNumPrecEvals(void*, long int*);
extern "C" int IDAGetNumPrecSolves(void*, long int*);
extern "C" int IDAGetNumLinIters(void*, long int*);
extern "C" int IDAGetNumLinConvFails(void*, long int*);
extern "C" int IDAGetNumJTSetupEvals(void*, long int*);
extern "C" int IDAGetNumJtimesEvals(void*, long int*);
extern "C" int IDAGetNumLinResEvals(void*, long int*);
