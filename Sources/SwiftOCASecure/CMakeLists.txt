#[[
This source file is part of the SwiftOCA open source project

Copyright (c) 2024 PADL Software Pty Ltd and the SwiftOCA project authors
Licensed under Apache License v2.0

See https://github.com/PADL/SwiftOCA/blob/main/LICENSE.md for license information
#]]

file(GLOB_RECURSE SWIFT_OCA_SECURE_SOURCES CONFIGURE_DEPENDS *.swift)

add_library(SwiftOCASecure ${SWIFT_OCA_SECURE_SOURCES})
target_link_libraries(SwiftOCASecure
  PUBLIC
    SwiftOCA
    SocketAddress::SocketAddress
    Logging::Logging)
if(CMAKE_SYSTEM_NAME STREQUAL Linux)
  target_link_libraries(SwiftOCASecure
    PUBLIC
      COpenSSL
      IORingSwift::IORing
      IORingSwift::IORingUtils
      # Ocp1OpenSSLDTLSConnection uses Data.socketAddress, defined in
      # IORingFoundation. SPM picks this up transitively because SwiftOCA's
      # IORingFoundation dep is part of its product link interface; but in
      # CMake we have to declare it explicitly since SwiftOCA imports it
      # @_implementationOnly (no compile-time re-export to consumers).
      IORingSwift::IORingFoundation)
endif()

target_compile_options(SwiftOCASecure PRIVATE
  "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-package-name SwiftOCA>"
  "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-swift-version 6>"
  "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-D NonEmbeddedBuild>"
  "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-enable-experimental-feature StrictConcurrency>")

get_swift_host_os(_swift_os)
set_target_properties(SwiftOCASecure PROPERTIES
  SOVERSION 0
  INTERFACE_INCLUDE_DIRECTORIES
    "$<BUILD_INTERFACE:${CMAKE_Swift_MODULE_DIRECTORY}>;$<INSTALL_INTERFACE:${CMAKE_INSTALL_LIBDIR}/swift/${_swift_os}>")

_install_target(SwiftOCASecure)
set_property(GLOBAL APPEND PROPERTY SWIFT_OCA_EXPORTS SwiftOCASecure)
