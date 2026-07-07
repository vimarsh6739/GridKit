#pragma once

#include <sundials/sundials_context.h>
#include <sundials/sundials_types.h>

#define CSR_MAT 0

struct _SUNMatrix;
using SUNMatrix = _SUNMatrix*;

extern "C" SUNMatrix SUNSparseMatrix(sunindextype,
                                      sunindextype,
                                      sunindextype,
                                      int,
                                      SUNContext);
extern "C" SUNMatrix SUNDenseMatrix(sunindextype, sunindextype, SUNContext);
extern "C" int SUNMatDestroy(SUNMatrix);
extern "C" int SUNMatZero(SUNMatrix);
extern "C" sunindextype* SUNSparseMatrix_IndexPointers(SUNMatrix);
extern "C" sunindextype* SUNSparseMatrix_IndexValues(SUNMatrix);
extern "C" sunrealtype* SUNSparseMatrix_Data(SUNMatrix);

