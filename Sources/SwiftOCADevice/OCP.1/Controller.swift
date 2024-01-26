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

import AsyncAlgorithms
import AsyncExtensions
import Foundation
import Logging
import SwiftOCA

#if os(macOS) || os(iOS)
typealias Ocp1Controller = Ocp1FlyingSocksController
public typealias Ocp1DeviceEndpoint = Ocp1FlyingSocksDeviceEndpoint
public typealias Ocp1WSDeviceEndpoint = Ocp1FlyingFoxDeviceEndpoint
#elseif os(Linux)
typealias Ocp1Controller = Ocp1IORingStreamController
public typealias Ocp1DeviceEndpoint = Ocp1IORingStreamDeviceEndpoint
#endif

public protocol OcaController: Actor {
    func addSubscription(
        _ subscription: OcaSubscriptionManagerSubscription
    ) async throws

    func removeSubscription(
        _ subscription: OcaSubscriptionManagerSubscription
    ) async throws

    func removeSubscription(
        _ event: OcaEvent,
        property: OcaPropertyID?,
        subscriber: OcaMethod
    ) async throws

    func sendMessage(
        _ message: Ocp1Message,
        type messageType: OcaMessageType
    ) async throws
}
