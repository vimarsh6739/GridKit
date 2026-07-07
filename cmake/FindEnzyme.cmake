#
#[[

Finds Enzyme Clang plugin

User may set:
- ENZYME_DIR

Author(s):
- Asher Mancinelli <ashermancinelli@gmail.com>
- Nicholson Koukpaizan <koukpaizannk@ornl.gov>

]]

# Error if CMAKE_BUILD_TYPE is not Release or RelWithDebInfo due to an Enzyme bug
if(NOT ((CMAKE_BUILD_TYPE STREQUAL "Release") OR (CMAKE_BUILD_TYPE STREQUAL "RelWithDebInfo")))
  message(STATUS "CMAKE_BUILD_TYPE: ${CMAKE_BUILD_TYPE}")
  message(FATAL_ERROR "Enzyme builds currently only support Release and RelWithDebInfo as \
                       CMAKE_BUILD_TYPE due to a bug within the Enzyme library.")
endif()

# Find Enzyme and necessary programs
option(GRIDKIT_ENZYME_USE_CLANG_PLUGIN
       "Load Enzyme through the Clang plugin target instead of an Enzyme-enabled compiler"
       ON)

find_package(
  Enzyme
  REQUIRED
  CONFIG
  PATHS
  ${ENZYME_DIR}
  ${ENZYME_DIR}/lib/cmake/Enzyme)
message(STATUS "Enzyme configuration found: ${Enzyme_CONFIG}")

find_library(
  ENZYME_LLVM_PLUGIN_LIBRARY
  NAMES LLVMEnzyme-${Enzyme_LLVM_VERSION_MAJOR}.so LLVMEnzyme-${Enzyme_LLVM_VERSION_MAJOR}.dylib
        LLVMEnzyme-${Enzyme_LLVM_VERSION_MAJOR}.dll
  PATHS ${ENZYME_DIR}
        ENV
        LD_LIBRARY_PATH
        ENV
        DYLD_LIBRARY_PATH
  PATH_SUFFIXES Enzyme lib64 lib REQUIRED)
message(STATUS "Enzyme LLVM plugin library: ${ENZYME_LLVM_PLUGIN_LIBRARY}")
if(TARGET LLVMEnzyme-${Enzyme_LLVM_VERSION_MAJOR})
  set_target_properties(LLVMEnzyme-${Enzyme_LLVM_VERSION_MAJOR}
                        PROPERTIES IMPORTED_LOCATION "${ENZYME_LLVM_PLUGIN_LIBRARY}"
                                   IMPORTED_LOCATION_RELEASE "${ENZYME_LLVM_PLUGIN_LIBRARY}")
endif()

if(GRIDKIT_ENZYME_USE_CLANG_PLUGIN)
  find_library(
    ENZYME_CLANG_PLUGIN_LIBRARY
    NAMES ClangEnzyme-${Enzyme_LLVM_VERSION_MAJOR}.so ClangEnzyme-${Enzyme_LLVM_VERSION_MAJOR}.dylib
          ClangEnzyme-${Enzyme_LLVM_VERSION_MAJOR}.dll
    PATHS ${ENZYME_DIR}
          ENV
          LD_LIBRARY_PATH
          ENV
          DYLD_LIBRARY_PATH
    PATH_SUFFIXES Enzyme lib64 lib REQUIRED)
  message(STATUS "Enzyme Clang plugin library: ${ENZYME_CLANG_PLUGIN_LIBRARY}")
  if(TARGET ClangEnzyme-${Enzyme_LLVM_VERSION_MAJOR})
    set_target_properties(ClangEnzyme-${Enzyme_LLVM_VERSION_MAJOR}
                          PROPERTIES IMPORTED_LOCATION "${ENZYME_CLANG_PLUGIN_LIBRARY}"
                                     IMPORTED_LOCATION_RELEASE "${ENZYME_CLANG_PLUGIN_LIBRARY}")
  endif()
else()
  message(STATUS "Enzyme Clang plugin disabled; assuming the C++ compiler provides Enzyme")
  if(TARGET ClangEnzymeFlags)
    set_target_properties(ClangEnzymeFlags PROPERTIES INTERFACE_COMPILE_OPTIONS "")
  endif()
endif()

find_program(
  GRIDKIT_LLVM_LINK llvm-link
  PATHS ${Enzyme_LLVM_BINARY_DIR}
  PATH_SUFFIXES bin REQUIRED)
message(STATUS "llvm-link: ${GRIDKIT_LLVM_LINK}")

find_program(
  GRIDKIT_OPT opt
  PATHS ${Enzyme_LLVM_BINARY_DIR}
  PATH_SUFFIXES bin REQUIRED)
message(STATUS "opt: ${GRIDKIT_OPT}")
