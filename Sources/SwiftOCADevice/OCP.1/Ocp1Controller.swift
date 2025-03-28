//
// Copyright (c) 2023 PADL Software Pty Ltd
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

#if os(macOS) || os(iOS)
typealias Ocp1Controller = Ocp1FlyingSocksStreamController
public typealias Ocp1DeviceEndpoint = Ocp1FlyingSocksStreamDeviceEndpoint
public typealias Ocp1WSDeviceEndpoint = Ocp1FlyingFoxDeviceEndpoint
#elseif os(Linux)
typealias Ocp1Controller = Ocp1IORingStreamController
public typealias Ocp1DeviceEndpoint = Ocp1IORingStreamDeviceEndpoint
#elseif canImport(Android)
typealias Ocp1Controller = Ocp1CFStreamController
public typealias Ocp1DeviceEndpoint = Ocp1CFStreamDeviceEndpoint
#endif
