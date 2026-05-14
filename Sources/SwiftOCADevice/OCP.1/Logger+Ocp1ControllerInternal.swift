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

extension Ocp1ControllerInternal {
  package nonisolated var loggerMetadata: Logger.Metadata {
    ["CONTROLLER": "\(connectionPrefix)/\(identifier)"]
  }
}

/// Render for trace logs; redact the payload when the target is the
/// SecurityManager so PSK key material never lands in traces.
private func _ocp1TraceDescription(_ message: Any) -> String {
  switch message {
  case let command as Ocp1Command where command.targetONo == OcaSecurityManagerONo:
    return
      "Ocp1Command(handle: \(command.handle), targetONo: \(command.targetONo), methodID: \(command.methodID), parameters: <redacted \(command.parameters.parameterData.count) bytes>)"
  default:
    return "\(message)"
  }
}

extension OcaDeviceEndpointPrivate {
  package nonisolated func traceMessage(
    _ message: some Any,
    controller: any Ocp1ControllerInternal,
    direction: OcaMessageDirection
  ) {
    guard enableMessageTracing, logger.logLevel <= .trace else { return }
    logger.trace(
      "message \(direction): \(_ocp1TraceDescription(message))",
      metadata: controller.loggerMetadata
    )
  }
}

extension Logger {
  package func info(_ message: String, controller: any Ocp1ControllerInternal) {
    info("\(message)", metadata: controller.loggerMetadata)
  }

  package func command(_ command: Ocp1Command, on controller: any Ocp1ControllerInternal) {
    trace("command \(_ocp1TraceDescription(command))", metadata: controller.loggerMetadata)
  }

  package func response(_ response: Ocp1Response, on controller: any Ocp1ControllerInternal) {
    trace("response \(response)", metadata: controller.loggerMetadata)
  }

  package func error(_ error: Error, controller: any Ocp1ControllerInternal) {
    warning("error \(error)", metadata: controller.loggerMetadata)
  }
}
