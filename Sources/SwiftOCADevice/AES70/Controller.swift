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
typealias AES70OCP1Controller = AES70OCP1FlyingSocksController
public typealias AES70OCP1DeviceEndpoint = AES70OCP1FlyingSocksDeviceEndpoint
public typealias AES70OCP1WSDeviceEndpoint = AES70OCP1FlyingFoxDeviceEndpoint
#elseif os(Linux)
typealias AES70OCP1Controller = AES70OCP1IORingStreamController
public typealias AES70OCP1DeviceEndpoint = AES70OCP1IORingStreamDeviceEndpoint
#endif

public protocol AES70Controller: Actor {
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
