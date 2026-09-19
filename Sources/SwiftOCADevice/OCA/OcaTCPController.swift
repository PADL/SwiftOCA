//
// Copyright (c) 2023-2026 PADL Software Pty Ltd
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

import SwiftOCA

// macOS, iOS, embedded Linux uses FlyingSocks because it does not pull in
// Foundation and because not all embedded Linux distributions have recent
// enough kernels to support io_uring

#if os(macOS) || os(iOS) || os(Windows) || !NonEmbeddedBuild
typealias OcaTCPController = OcaFlyingSocksStreamController
public typealias OcaTCPDeviceEndpoint = OcaFlyingSocksStreamDeviceEndpoint
@available(*, deprecated, renamed: "OcaTCPDeviceEndpoint")
public typealias Ocp1DeviceEndpoint = OcaTCPDeviceEndpoint
#elseif os(Linux)
typealias OcaTCPController = OcaIORingStreamController
public typealias OcaTCPDeviceEndpoint = OcaIORingStreamDeviceEndpoint
@available(*, deprecated, renamed: "OcaTCPDeviceEndpoint")
public typealias Ocp1DeviceEndpoint = OcaTCPDeviceEndpoint
#elseif canImport(Android)
typealias OcaTCPController = Ocp1CFStreamController
public typealias OcaTCPDeviceEndpoint = Ocp1CFStreamDeviceEndpoint
@available(*, deprecated, renamed: "OcaTCPDeviceEndpoint")
public typealias Ocp1DeviceEndpoint = OcaTCPDeviceEndpoint
#endif

#if canImport(FlyingFox) && NonEmbeddedBuild
public typealias OcaWSDeviceEndpoint = OcaFlyingFoxDeviceEndpoint
@available(*, deprecated, renamed: "OcaWSDeviceEndpoint")
public typealias Ocp1WSDeviceEndpoint = OcaWSDeviceEndpoint
#endif
