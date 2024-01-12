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

import Foundation
import Logging
import SwiftOCA

public protocol AES70DeviceEndpoint {
    var controllers: [AES70Controller] { get async }
}

protocol AES70DeviceEndpointPrivate: AES70DeviceEndpoint {
    associatedtype ControllerType: AES70ControllerPrivate

    var logger: Logger { get }
    var timeout: TimeInterval { get }

    func add(controller: ControllerType) async
    func remove(controller: ControllerType) async
}
