//
// Copyright (c) 2024-2025 PADL Software Pty Ltd
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

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Logging
import SwiftOCA

private extension Ocp1ControllerInternal {
  nonisolated var loggerMetadata: Logger.Metadata {
    ["CONTROLLER": "\(connectionPrefix)/\(identifier)"]
  }
}

extension OcaDeviceEndpointPrivate {
  nonisolated func traceMessage(
    _ message: some Any,
    controller: any Ocp1ControllerInternal,
    direction: OcaMessageDirection
  ) {
    guard enableMessageTracing else { return }
    logger.trace("message \(direction): \(message)", metadata: controller.loggerMetadata)
  }
}

extension Logger {
  func info(_ message: String, controller: any Ocp1ControllerInternal) {
    info("\(message)", metadata: controller.loggerMetadata)
  }

  func command(_ command: Ocp1Command, on controller: any Ocp1ControllerInternal) {
    trace("command \(command)", metadata: controller.loggerMetadata)
  }

  func response(_ response: Ocp1Response, on controller: any Ocp1ControllerInternal) {
    trace("response \(response)", metadata: controller.loggerMetadata)
  }

  func error(_ error: Error, controller: any Ocp1ControllerInternal) {
    warning("error \(error)", metadata: controller.loggerMetadata)
  }
}
