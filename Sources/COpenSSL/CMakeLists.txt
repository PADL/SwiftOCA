#[[
This source file is part of the SwiftOCA open source project

Copyright (c) 2024 PADL Software Pty Ltd and the SwiftOCA project authors
Licensed under Apache License v2.0

See https://github.com/PADL/SwiftOCA/blob/main/LICENSE.md for license information
#]]

# INTERFACE wrapper exposing the `COpenSSL` Swift module on Linux. The
# module.modulemap's `link "ssl"` / `link "crypto"` pull in the system libs.
add_library(COpenSSL INTERFACE)
target_include_directories(COpenSSL INTERFACE
  $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}>
  $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}/COpenSSL>)

install(FILES
  shim.h
  module.modulemap
  DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/COpenSSL)

_install_target(COpenSSL)
set_property(GLOBAL APPEND PROPERTY SWIFT_OCA_EXPORTS COpenSSL)
