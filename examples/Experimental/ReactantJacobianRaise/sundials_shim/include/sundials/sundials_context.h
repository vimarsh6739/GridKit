#pragma once

#include <sundials/sundials_types.h>

#define SUN_COMM_NULL nullptr

using SUNContext = void*;

extern "C" int SUNContext_Create(void*, SUNContext*);
extern "C" int SUNContext_Free(SUNContext*);

