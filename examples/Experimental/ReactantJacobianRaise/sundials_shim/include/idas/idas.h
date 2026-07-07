#pragma once

#include <cstdio>

#include <nvector/nvector_serial.h>
#include <sundials/sundials_context.h>
#include <sundials/sundials_types.h>

#define IDA_SUCCESS 0
#define IDA_NORMAL 1
#define IDA_Y_INIT 1
#define IDA_YA_YDP_INIT 2
#define IDA_HERMITE 1
#define SUNTRUE 1
#define SUNFALSE 0
#define SUN_OUTPUTFORMAT_TABLE 0

extern "C" void* IDACreate(SUNContext);
extern "C" int IDAInit(void*, ...);
extern "C" int IDAReInit(void*, ...);
extern "C" int IDAFree(void**);
extern "C" int IDASetUserData(void*, void*);
extern "C" int IDASetId(void*, N_Vector);
extern "C" int IDASetMinStep(void*, sunrealtype);
extern "C" int IDASetMaxStep(void*, sunrealtype);
extern "C" int IDASetMaxNumSteps(void*, long int);
extern "C" int IDASetSuppressAlg(void*, int);
extern "C" int IDASetMaxOrd(void*, int);
extern "C" int IDASetMaxNonlinIters(void*, int);
extern "C" int IDASetNonlinConvCoef(void*, sunrealtype);
extern "C" int IDASStolerances(void*, sunrealtype, sunrealtype);
extern "C" int IDASVtolerances(void*, sunrealtype, N_Vector);
extern "C" int IDACalcIC(void*, int, sunrealtype);
extern "C" int IDAGetConsistentIC(void*, N_Vector, N_Vector);
extern "C" int IDASolve(void*, sunrealtype, sunrealtype*, N_Vector, N_Vector, int);
extern "C" int IDAPrintAllStats(void*, std::FILE*, int);
extern "C" int IDAGetIntegratorStats(void*,
                                      long int*,
                                      long int*,
                                      long int*,
                                      long int*,
                                      int*,
                                      int*,
                                      sunrealtype*,
                                      sunrealtype*,
                                      sunrealtype*,
                                      sunrealtype*);
extern "C" int IDAGetNonlinSolvStats(void*, long int*, long int*);

extern "C" int IDAQuadInit(void*, ...);
extern "C" int IDAQuadReInit(void*, N_Vector);
extern "C" int IDAQuadFree(void*);
extern "C" int IDASetQuadErrCon(void*, int);
extern "C" int IDAQuadSStolerances(void*, sunrealtype, sunrealtype);
extern "C" int IDAQuadSVtolerances(void*, sunrealtype, N_Vector);
extern "C" int IDAGetQuad(void*, sunrealtype*, N_Vector);

extern "C" int IDAAdjInit(void*, long int, int);
extern "C" int IDAAdjFree(void*);
extern "C" int IDACreateB(void*, int*);
extern "C" int IDAInitB(void*, int, ...);
extern "C" void* IDAGetAdjIDABmem(void*, int);
extern "C" int IDASetUserDataB(void*, int, void*);
extern "C" int IDASetQuadErrConB(void*, int, int);
extern "C" int IDAQuadInitB(void*, int, ...);
extern "C" int IDASolveF(void*, sunrealtype, sunrealtype*, N_Vector, N_Vector, int, int*);
extern "C" int IDASolveB(void*, sunrealtype, int);
extern "C" int IDAGetNumSteps(void*, long int*);
extern "C" int IDAGetB(void*, int, sunrealtype*, N_Vector, N_Vector);
extern "C" int IDAGetQuadB(void*, int, sunrealtype*, N_Vector);

