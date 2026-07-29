//
// Copyright (c) 2026 PADL Software Pty Ltd
//
// Licensed under the Apache License, Version 2.0 (the License);
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an 'AS IS' BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// Writing to a socket whose peer has already closed raises SIGPIPE, and its
/// default disposition terminates the process. A test that disconnects while
/// the far end is still writing then kills the runner part way through the
/// suite, which reports as a crash with no failing test rather than as a
/// failure. Setting the disposition is the application's business, not the
/// library's, and for these tests the runner is the application.
let ignoreSIGPIPEOnce: Void = {
  signal(SIGPIPE, SIG_IGN)
}()
