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

open class OcaSignalGenerator: OcaActuator, @unchecked Sendable {
  override open class var classID: OcaClassID { OcaClassID("1.1.1.17") }
  override open class var classVersion: OcaClassVersionNumber { 3 }

  /// centre frequency, or sweep start frequency
  @OcaBoundedProperty(
    propertyID: OcaPropertyID("4.1"),
    getMethodID: OcaMethodID("4.1"),
    setMethodID: OcaMethodID("4.2")
  )
  public var frequency1: OcaBoundedProperty<OcaFrequency>.PropertyValue

  /// sweep end frequency
  @OcaBoundedProperty(
    propertyID: OcaPropertyID("4.2"),
    getMethodID: OcaMethodID("4.3"),
    setMethodID: OcaMethodID("4.4")
  )
  public var frequency2: OcaBoundedProperty<OcaFrequency>.PropertyValue

  /// output level relative to the device-defined zero level
  @OcaBoundedProperty(
    propertyID: OcaPropertyID("4.3"),
    getMethodID: OcaMethodID("4.5"),
    setMethodID: OcaMethodID("4.6")
  )
  public var level: OcaBoundedProperty<OcaDBz>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("4.4"),
    getMethodID: OcaMethodID("4.7"),
    setMethodID: OcaMethodID("4.8")
  )
  public var waveform: OcaProperty<OcaWaveformType>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("4.5"),
    getMethodID: OcaMethodID("4.9"),
    setMethodID: OcaMethodID("4.10")
  )
  public var sweepType: OcaProperty<OcaSweepType>.PropertyValue

  @OcaBoundedProperty(
    propertyID: OcaPropertyID("4.6"),
    getMethodID: OcaMethodID("4.11"),
    setMethodID: OcaMethodID("4.12")
  )
  public var sweepTime: OcaBoundedProperty<OcaTimeInterval>.PropertyValue

  /// whether the sweep repeats, or is one-shot
  @OcaProperty(
    propertyID: OcaPropertyID("4.7"),
    getMethodID: OcaMethodID("4.13"),
    setMethodID: OcaMethodID("4.14")
  )
  public var sweepRepeat: OcaProperty<OcaBoolean>.PropertyValue

  /// whether the generator is currently producing output
  @OcaProperty(
    propertyID: OcaPropertyID("4.8"),
    getMethodID: OcaMethodID("4.15")
  )
  public var generating: OcaProperty<OcaBoolean>.PropertyValue

  public func start() async throws {
    try await sendCommandRrq(methodID: OcaMethodID("4.16"))
  }

  public func stop() async throws {
    try await sendCommandRrq(methodID: OcaMethodID("4.17"))
  }

  @_spi(SwiftOCAPrivate)
  public struct SetMultipleParameters: Ocp1ParametersReflectable {
    public let mask: OcaParameterMask
    public let frequency1: OcaFrequency
    public let frequency2: OcaFrequency
    public let level: OcaDBz
    public let waveform: OcaWaveformType
    public let sweepType: OcaSweepType
    public let sweepTime: OcaTimeInterval
    public let sweepRepeat: OcaBoolean

    public init(
      mask: OcaParameterMask,
      frequency1: OcaFrequency,
      frequency2: OcaFrequency,
      level: OcaDBz,
      waveform: OcaWaveformType,
      sweepType: OcaSweepType,
      sweepTime: OcaTimeInterval,
      sweepRepeat: OcaBoolean
    ) {
      self.mask = mask
      self.frequency1 = frequency1
      self.frequency2 = frequency2
      self.level = level
      self.waveform = waveform
      self.sweepType = sweepType
      self.sweepTime = sweepTime
      self.sweepRepeat = sweepRepeat
    }
  }

  /// atomically sets the generation parameters selected by `mask`
  public func setMultiple(
    mask: OcaParameterMask,
    frequency1: OcaFrequency,
    frequency2: OcaFrequency,
    level: OcaDBz,
    waveform: OcaWaveformType,
    sweepType: OcaSweepType,
    sweepTime: OcaTimeInterval,
    sweepRepeat: OcaBoolean
  ) async throws {
    try await sendCommandRrq(
      methodID: OcaMethodID("4.18"),
      parameters: SetMultipleParameters(
        mask: mask,
        frequency1: frequency1,
        frequency2: frequency2,
        level: level,
        waveform: waveform,
        sweepType: sweepType,
        sweepTime: sweepTime,
        sweepRepeat: sweepRepeat
      )
    )
  }
}
