#

# [[
#  Author(s):
#    - Cameron Rutherford <cameron.rutherford@pnnl.gov>
#]]

set(_install_headers DynamicSolver.hpp Ida.hpp IdaJvpRuntime.hpp)
set(_solver_sources Ida.cpp IdaJvpRuntime.cpp)
set(_solver_link_libraries
    PUBLIC
    SUNDIALS::nvecserial
    PUBLIC
    SUNDIALS::idas)

if(GRIDKIT_ENABLE_SUNDIALS_SPARSE)
  list(APPEND _solver_link_libraries PUBLIC SUNDIALS::sunlinsolklu)
endif()

if(TARGET SUNDIALS::sunlinsolspgmr)
  list(APPEND _solver_link_libraries PUBLIC SUNDIALS::sunlinsolspgmr)
endif()

list(
  APPEND
  _solver_link_libraries
  PUBLIC
  GridKit::definitions
  PUBLIC
  GridKit::utilities_logger
  PUBLIC
  GridKit::sparse_matrix)

gridkit_add_library(
  solvers_dyn
  SOURCES ${_solver_sources}
  HEADERS ${_install_headers}
  LINK_LIBRARIES ${_solver_link_libraries})
