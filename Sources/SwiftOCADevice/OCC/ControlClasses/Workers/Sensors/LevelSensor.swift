//
// Copyright (c) 2023-2025 PADL Software Pty Ltd
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

@_spi(SwiftOCAPrivate)
import SwiftOCA

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

open class OcaLevelSensor: OcaSensor {
  override open class var classID: OcaClassID { OcaClassID("1.1.2.2") }

  // because Codable is so inefficient, open code this
  private var _value: OcaDB = -144.0
  private var _range: ClosedRange<OcaDB> = -144.0...0.0

  override public func handleCommand(
    _ command: Ocp1Command,
    from controller: OcaController
  ) async throws -> Ocp1Response {
    switch command.methodID {
    case OcaMethodID("4.1"):
      try decodeNullCommand(command)
      try await ensureReadable(by: controller, command: command)
      let value = OcaBoundedPropertyValue<OcaDB>(value: _value, in: _range)
      return try encodeResponse(value)
    default:
      return try await super.handleCommand(command, from: controller)
    }
  }

  private func _valueDidChange(_ newValue: OcaDB) async throws {
    guard let deviceDelegate else {
      throw Ocp1Error.notConnected
    }

    let event = OcaEvent(emitterONo: objectNumber, eventID: OcaPropertyChangedEventID)
    let parameters = OcaPropertyChangedEventData<OcaDB>(
      propertyID: OcaPropertyID(defLevel: 4, propertyIndex: 1),
      propertyValue: newValue,
      changeType: .currentChanged
    )

    var bytes = [UInt8]()
    bytes.reserveCapacity(9)
    parameters.encode(into: &bytes)

    try await deviceDelegate.notifySubscribers(event, parameters: Data(bytes))
  }

  // for API compatibility, but prefer to use update(reading:) to set value
  public var reading: OcaBoundedPropertyValue<OcaDB> {
    get {
      OcaBoundedPropertyValue(value: _value, in: _range)
    }
    set {
      let valueDidChange = newValue.value != _value
      _value = newValue.value
      _range = newValue.range
      if valueDidChange {
        Task { try await _valueDidChange(newValue.value) }
      }
    }
  }

  public func update(reading newValue: OcaDB, alwaysNotifySubscribers: Bool = false) async throws {
    let valueDidChange = newValue != _value
    _value = newValue
    if valueDidChange || alwaysNotifySubscribers {
      try await _valueDidChange(newValue)
    }
  }
}
