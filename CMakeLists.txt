#[[
This source file is part of the SwiftOCA open source project

Copyright (c) 2024 PADL Software Pty Ltd and the SwiftOCA project authors
Licensed under Apache License v2.0

See https://github.com/PADL/SwiftOCA/blob/main/LICENSE.md for license information
#]]

cmake_minimum_required(VERSION 3.16)
project(SwiftOCA
  LANGUAGES Swift C)

list(APPEND CMAKE_MODULE_PATH ${PROJECT_SOURCE_DIR}/cmake/modules)

set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
set(CMAKE_Swift_MODULE_DIRECTORY ${CMAKE_BINARY_DIR}/swift)

if(CMAKE_SYSTEM_NAME STREQUAL Windows OR CMAKE_SYSTEM_NAME STREQUAL Darwin)
  option(BUILD_SHARED_LIBS "Build shared libraries by default" YES)
endif()

include(GNUInstallDirs)
include(SwiftSupport)

find_package(SwiftSystem REQUIRED)
find_package(SwiftAtomics REQUIRED)
find_package(SocketAddress REQUIRED)
find_package(AsyncExtensions REQUIRED)
find_package(AsyncAlgorithms REQUIRED)
find_package(Logging REQUIRED)
find_package(AnyCodable REQUIRED)
find_package(FlyingFox REQUIRED)

if(CMAKE_SYSTEM_NAME STREQUAL Linux)
  find_package(IORingSwift REQUIRED)
  find_package(OpenSSL REQUIRED)
endif()

add_subdirectory(Sources)
add_subdirectory(cmake/modules)
