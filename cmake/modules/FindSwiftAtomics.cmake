#[[
This source file is part of the AsyncExtensions open source project

Copyright (c) 2024 The AsyncExtensions project authors
Licensed under MIT License

See https://github.com/sideeffect-io/AsyncExtensions/blob/main/LICENSE for license information
#]]

# FindSwiftAtomics.cmake
#
# Locates an installed apple/swift-atomics package built with its upstream
# CMake. Upstream installs `libAtomics.so` and the swiftmodule but does NOT
# install the `_AtomicsShims` headers / module.modulemap that `import Atomics`
# transitively imports at compile time. The prefix must have those staged
# under `include/_AtomicsShims/`.

if(CMAKE_SYSTEM_NAME STREQUAL Darwin)
  set(_swift_os macosx)
else()
  string(TOLOWER "${CMAKE_SYSTEM_NAME}" _swift_os)
endif()

find_library(SwiftAtomics_LIBRARY
  NAMES Atomics
  PATH_SUFFIXES lib/swift/${_swift_os} lib)

find_path(SwiftAtomics_MODULE_DIR
  NAMES Atomics.swiftmodule
  PATH_SUFFIXES lib/swift/${_swift_os})

find_path(SwiftAtomics_SHIMS_INCLUDE_DIR
  NAMES _AtomicsShims/module.modulemap
  PATH_SUFFIXES include)

include(FindPackageHandleStandardArgs)
find_package_handle_standard_args(SwiftAtomics
  REQUIRED_VARS
    SwiftAtomics_LIBRARY
    SwiftAtomics_MODULE_DIR
    SwiftAtomics_SHIMS_INCLUDE_DIR)

if(SwiftAtomics_FOUND AND NOT TARGET SwiftAtomics::Atomics)
  add_library(SwiftAtomics::Atomics SHARED IMPORTED)
  set_target_properties(SwiftAtomics::Atomics PROPERTIES
    IMPORTED_LOCATION "${SwiftAtomics_LIBRARY}"
    INTERFACE_INCLUDE_DIRECTORIES
      "${SwiftAtomics_MODULE_DIR};${SwiftAtomics_SHIMS_INCLUDE_DIR}")
endif()

mark_as_advanced(
  SwiftAtomics_LIBRARY
  SwiftAtomics_MODULE_DIR
  SwiftAtomics_SHIMS_INCLUDE_DIR)
