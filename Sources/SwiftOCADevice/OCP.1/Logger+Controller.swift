//
// Copyright (c) 2024 PADL Software Pty Ltd
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

extension Logger {
    func info(_ message: String, controller: Ocp1ControllerInternal) {
        info("<\(type(of: controller).connectionPrefix)/\(controller.identifier)> \(message)")
    }

    func command(_ command: Ocp1Command, on controller: Ocp1ControllerInternal) {
        trace(
            "<\(type(of: controller).connectionPrefix)/\(controller.identifier)> command \(command)"
        )
    }

    func response(_ response: Ocp1Response, on controller: Ocp1ControllerInternal) {
        trace(
            "<\(type(of: controller).connectionPrefix)/\(controller.identifier)> response \(response)"
        )
    }

    func error(_ error: Error, controller: Ocp1ControllerInternal) {
        warning(
            "<\(type(of: controller).connectionPrefix)/\(controller.identifier)> error \(error)"
        )
    }
}
