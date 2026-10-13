#[[
This source file is part of the SwiftOCA open source project

Copyright (c) 2024 PADL Software Pty Ltd and the SwiftOCA project authors
Licensed under Apache License v2.0

See https://github.com/PADL/SwiftOCA/blob/main/LICENSE.md for license information
#]]

# INTERFACE wrapper exposing the `dnssd` Swift module on Linux. The
# module.modulemap's `link "dns_sd"` pulls in libdns_sd at link time.
add_library(dnssd INTERFACE)
target_include_directories(dnssd INTERFACE
  $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}>
  $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}/dnssd>)

install(FILES
  dnssd.h
  module.modulemap
  DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/dnssd)

_install_target(dnssd)
set_property(GLOBAL APPEND PROPERTY SWIFT_OCA_EXPORTS dnssd)
