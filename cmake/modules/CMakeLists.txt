#[[
This source file is part of the SwiftOCA open source project

Copyright (c) 2024 PADL Software Pty Ltd and the SwiftOCA project authors
Licensed under Apache License v2.0

See https://github.com/PADL/SwiftOCA/blob/main/LICENSE.md for license information
#]]

include(CMakePackageConfigHelpers)

set(SWIFT_OCA_EXPORTS_FILE
  ${CMAKE_CURRENT_BINARY_DIR}/SwiftOCAExports.cmake)

configure_file(SwiftOCAConfig.cmake.in
  ${CMAKE_CURRENT_BINARY_DIR}/SwiftOCAConfig.cmake)

get_property(SWIFT_OCA_EXPORTS GLOBAL PROPERTY SWIFT_OCA_EXPORTS)
export(TARGETS ${SWIFT_OCA_EXPORTS}
  NAMESPACE SwiftOCA::
  FILE ${SWIFT_OCA_EXPORTS_FILE}
  EXPORT_LINK_INTERFACE_LIBRARIES)

install(EXPORT SwiftOCATargets
  FILE SwiftOCATargets.cmake
  NAMESPACE SwiftOCA::
  DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/SwiftOCA)

configure_package_config_file(
  SwiftOCAConfig.cmake.in
  ${CMAKE_CURRENT_BINARY_DIR}/install/SwiftOCAConfig.cmake
  INSTALL_DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/SwiftOCA)

install(FILES
  ${CMAKE_CURRENT_BINARY_DIR}/install/SwiftOCAConfig.cmake
  FindSwiftSystem.cmake
  FindSwiftAtomics.cmake
  DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/SwiftOCA)
