#[[
This source file is part of the SwiftOCA open source project

Copyright (c) 2024 PADL Software Pty Ltd and the SwiftOCA project authors
Licensed under Apache License v2.0

See https://github.com/PADL/SwiftOCA/blob/main/LICENSE.md for license information
#]]

# Linux-only system-library wrappers.
if(CMAKE_SYSTEM_NAME STREQUAL Linux)
  add_subdirectory(dnssd)
  add_subdirectory(COpenSSL)
endif()

add_subdirectory(SwiftOCA)
add_subdirectory(SwiftOCASecure)
