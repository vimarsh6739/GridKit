#pragma once

#include <nvector/nvector_serial.h>
#include <sunmatrix/sunmatrix_sparse.h>

struct _SUNLinearSolver;
using SUNLinearSolver = _SUNLinearSolver*;

extern "C" SUNLinearSolver SUNLinSol_Dense(N_Vector, SUNMatrix, SUNContext);
extern "C" int SUNLinSolFree(SUNLinearSolver);

