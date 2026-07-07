#pragma once

#include <sunlinsol/sunlinsol_dense.h>

extern "C" SUNLinearSolver SUNLinSol_KLU(N_Vector, SUNMatrix, SUNContext);

