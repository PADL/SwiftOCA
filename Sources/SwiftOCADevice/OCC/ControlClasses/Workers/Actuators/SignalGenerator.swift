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

@_spi(SwiftOCAPrivate)
import SwiftOCA

open class OcaSignalGenerator: OcaActuator {
  override open class var classID: OcaClassID { OcaClassID("1.1.1.17") }
  override open class var classVersion: OcaClassVersionNumber { 3 }

  /// centre frequency, or sweep start frequency
  @OcaBoundedDeviceProperty(
    propertyID: OcaPropertyID("4.1"),
    getMethodID: OcaMethodID("4.1"),
    setMethodID: OcaMethodID("4.2")
  )
  public var frequency1 = OcaBoundedPropertyValue<OcaFrequency>(value: 1000, in: 10...20000)

  /// sweep end frequency
  @OcaBoundedDeviceProperty(
    propertyID: OcaPropertyID("4.2"),
    getMethodID: OcaMethodID("4.3"),
    setMethodID: OcaMethodID("4.4")
  )
  public var frequency2 = OcaBoundedPropertyValue<OcaFrequency>(value: 20000, in: 10...20000)

  /// output level relative to the device-defined zero level
  @OcaBoundedDeviceProperty(
    propertyID: OcaPropertyID("4.3"),
    getMethodID: OcaMethodID("4.5"),
    setMethodID: OcaMethodID("4.6")
  )
  public var level = OcaBoundedPropertyValue<OcaDBz>(value: -144.0, in: -144.0...20.0)

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("4.4"),
    getMethodID: OcaMethodID("4.7"),
    setMethodID: OcaMethodID("4.8")
  )
  public var waveform: OcaWaveformType = .none

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("4.5"),
    getMethodID: OcaMethodID("4.9"),
    setMethodID: OcaMethodID("4.10")
  )
  public var sweepType: OcaSweepType = .none

  @OcaBoundedDeviceProperty(
    propertyID: OcaPropertyID("4.6"),
    getMethodID: OcaMethodID("4.11"),
    setMethodID: OcaMethodID("4.12")
  )
  public var sweepTime = OcaBoundedPropertyValue<OcaTimeInterval>(value: 0, in: 0...60)

  /// whether the sweep repeats, or is one-shot
  @OcaDeviceProperty(
    propertyID: OcaPropertyID("4.7"),
    getMethodID: OcaMethodID("4.13"),
    setMethodID: OcaMethodID("4.14")
  )
  public var sweepRepeat: OcaBoolean = false

  /// whether the generator is currently producing output
  @OcaDeviceProperty(
    propertyID: OcaPropertyID("4.8"),
    getMethodID: OcaMethodID("4.15")
  )
  public var generating: OcaBoolean = false

  /// signal generation is device specific; the default implementation is unimplemented
  open func start() async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  /// signal generation is device specific; the default implementation is unimplemented
  open func stop() async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  /// atomic multiple-parameter assignment is device specific; the default implementation
  /// is unimplemented
  open func setMultiple(
    mask: OcaParameterMask,
    frequency1: OcaFrequency,
    frequency2: OcaFrequency,
    level: OcaDBz,
    waveform: OcaWaveformType,
    sweepType: OcaSweepType,
    sweepTime: OcaTimeInterval,
    sweepRepeat: OcaBoolean
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  override open func handleCommand(
    _ command: Ocp1Command,
    from controller: OcaController
  ) async throws -> Ocp1Response {
    switch command.methodID {
    case OcaMethodID("4.16"):
      try decodeNullCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await start()
      return Ocp1Response()
    case OcaMethodID("4.17"):
      try decodeNullCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await stop()
      return Ocp1Response()
    case OcaMethodID("4.18"):
      let parameters: SwiftOCA.OcaSignalGenerator.SetMultipleParameters =
        try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await setMultiple(
        mask: parameters.mask,
        frequency1: parameters.frequency1,
        frequency2: parameters.frequency2,
        level: parameters.level,
        waveform: parameters.waveform,
        sweepType: parameters.sweepType,
        sweepTime: parameters.sweepTime,
        sweepRepeat: parameters.sweepRepeat
      )
      return Ocp1Response()
    default:
      return try await super.handleCommand(command, from: controller)
    }
  }
}
