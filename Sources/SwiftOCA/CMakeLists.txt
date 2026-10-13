#[[
This source file is part of the SwiftOCA open source project

Copyright (c) 2024 PADL Software Pty Ltd and the SwiftOCA project authors
Licensed under Apache License v2.0

See https://github.com/PADL/SwiftOCA/blob/main/LICENSE.md for license information
#]]

file(GLOB_RECURSE SWIFT_OCA_SOURCES CONFIGURE_DEPENDS *.swift)

add_library(SwiftOCA ${SWIFT_OCA_SOURCES})
target_link_libraries(SwiftOCA
  PUBLIC
    SwiftSystem::SystemPackage
    SwiftAtomics::Atomics
    SocketAddress::SocketAddress
    AsyncExtensions::AsyncExtensions
    AsyncAlgorithms::AsyncAlgorithms
    Logging::Logging
    AnyCodable::AnyCodable
    FlyingFox::FlyingSocks)
if(CMAKE_SYSTEM_NAME STREQUAL Linux)
  target_link_libraries(SwiftOCA
    PUBLIC
      dnssd
      FlyingFox::FlyingFox
      IORingSwift::IORing
      IORingSwift::IORingUtils
      IORingSwift::IORingFoundation)
endif()

target_compile_options(SwiftOCA PRIVATE
  "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-package-name SwiftOCA>"
  "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-swift-version 6>"
  "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-D NonEmbeddedBuild>"
  "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-enable-experimental-feature StrictConcurrency>"
  "$<$<COMPILE_LANGUAGE:Swift>:SHELL:-enable-experimental-feature Extern>")

get_swift_host_os(_swift_os)
set_target_properties(SwiftOCA PROPERTIES
  SOVERSION 0
  INTERFACE_INCLUDE_DIRECTORIES
    "$<BUILD_INTERFACE:${CMAKE_Swift_MODULE_DIRECTORY}>;$<INSTALL_INTERFACE:${CMAKE_INSTALL_LIBDIR}/swift/${_swift_os}>")

_install_target(SwiftOCA)
set_property(GLOBAL APPEND PROPERTY SWIFT_OCA_EXPORTS SwiftOCA)
