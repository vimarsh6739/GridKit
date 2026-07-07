#pragma once

#include <sundials/sundials_context.h>
#include <sundials/sundials_types.h>

struct _N_Vector;
using N_Vector = _N_Vector*;

extern "C" N_Vector N_VNew_Serial(sunindextype, SUNContext);
extern "C" N_Vector N_VClone(N_Vector);
extern "C" void N_VDestroy(N_Vector);
extern "C" void N_VConst(sunrealtype, N_Vector);
extern "C" void N_VScale(sunrealtype, N_Vector, N_Vector);
extern "C" sunrealtype* N_VGetArrayPointer(N_Vector);
extern "C" sunindextype N_VGetLength(N_Vector);

