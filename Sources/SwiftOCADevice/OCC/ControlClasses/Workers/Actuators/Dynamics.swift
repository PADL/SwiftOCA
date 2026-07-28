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

open class OcaDynamics: OcaActuator {
  override open class var classID: OcaClassID { OcaClassID("1.1.1.14") }
  override open class var classVersion: OcaClassVersionNumber { 3 }

  /// whether the signal level is currently outside the threshold
  @OcaDeviceProperty(
    propertyID: OcaPropertyID("4.1"),
    getMethodID: OcaMethodID("4.1")
  )
  public var triggered: OcaBoolean = false

  /// the instantaneous gain of the dynamics element
  @OcaDeviceProperty(
    propertyID: OcaPropertyID("4.2"),
    getMethodID: OcaMethodID("4.2")
  )
  public var dynamicGain: OcaDB = 0.0

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("4.3"),
    getMethodID: OcaMethodID("4.3"),
    setMethodID: OcaMethodID("4.4")
  )
  public var function: OcaDynamicsFunction = .none

  @available(*, deprecated, message: "deprecated by AES70, use slope instead")
  @OcaBoundedDeviceProperty(
    propertyID: OcaPropertyID("4.4"),
    getMethodID: OcaMethodID("4.5"),
    setMethodID: OcaMethodID("4.6")
  )
  public var ratio = OcaBoundedPropertyValue<OcaFloat32>(value: 1, in: 1...100)

  @OcaBoundedDeviceProperty(
    propertyID: OcaPropertyID("4.5"),
    getMethodID: OcaMethodID("4.7"),
    setMethodID: OcaMethodID("4.8")
  )
  public var threshold = OcaBoundedPropertyValue<OcaDBr>(value: 0.0, in: -144.0...20.0)

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("4.6"),
    getMethodID: OcaMethodID("4.9"),
    setMethodID: OcaMethodID("4.10")
  )
  public var thresholdPresentationUnits: OcaPresentationUnit = .dBu

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("4.7"),
    getMethodID: OcaMethodID("4.11"),
    setMethodID: OcaMethodID("4.12")
  )
  public var detectorLaw: OcaLevelDetectionLaw = .none

  @OcaBoundedDeviceProperty(
    propertyID: OcaPropertyID("4.8"),
    getMethodID: OcaMethodID("4.13"),
    setMethodID: OcaMethodID("4.14")
  )
  public var attackTime = OcaBoundedPropertyValue<OcaTimeInterval>(value: 0, in: 0...1)

  @OcaBoundedDeviceProperty(
    propertyID: OcaPropertyID("4.9"),
    getMethodID: OcaMethodID("4.15"),
    setMethodID: OcaMethodID("4.16")
  )
  public var releaseTime = OcaBoundedPropertyValue<OcaTimeInterval>(value: 0, in: 0...1)

  @OcaBoundedDeviceProperty(
    propertyID: OcaPropertyID("4.10"),
    getMethodID: OcaMethodID("4.17"),
    setMethodID: OcaMethodID("4.18")
  )
  public var holdTime = OcaBoundedPropertyValue<OcaTimeInterval>(value: 0, in: 0...1)

  @OcaBoundedDeviceProperty(
    propertyID: OcaPropertyID("4.11"),
    getMethodID: OcaMethodID("4.21"),
    setMethodID: OcaMethodID("4.22")
  )
  public var dynamicGainCeiling = OcaBoundedPropertyValue<OcaDB>(
    value: 0.0,
    in: -144.0...20.0
  )

  @OcaBoundedDeviceProperty(
    propertyID: OcaPropertyID("4.12"),
    getMethodID: OcaMethodID("4.19"),
    setMethodID: OcaMethodID("4.20")
  )
  public var dynamicGainFloor = OcaBoundedPropertyValue<OcaDB>(
    value: -144.0,
    in: -144.0...20.0
  )

  /// soft knee parameter, interpreted in a device-dependent manner
  @OcaBoundedDeviceProperty(
    propertyID: OcaPropertyID("4.13"),
    getMethodID: OcaMethodID("4.23"),
    setMethodID: OcaMethodID("4.24")
  )
  public var kneeParameter = OcaBoundedPropertyValue<OcaFloat32>(value: 0, in: 0...1)

  /// d(output amplitude) / d(input amplitude), independently of ``function``
  @OcaBoundedDeviceProperty(
    propertyID: OcaPropertyID("4.14"),
    getMethodID: OcaMethodID("4.25"),
    setMethodID: OcaMethodID("4.26")
  )
  public var slope = OcaBoundedPropertyValue<OcaFloat32>(value: 1, in: 0...100)

  /// atomic multiple-parameter assignment is device specific; the default implementation
  /// is unimplemented
  open func setMultiple(
    mask: OcaParameterMask,
    function: OcaDynamicsFunction,
    threshold: OcaDBr,
    thresholdPresentationUnits: OcaPresentationUnit,
    detectorLaw: OcaLevelDetectionLaw,
    attackTime: OcaTimeInterval,
    releaseTime: OcaTimeInterval,
    holdTime: OcaTimeInterval,
    dynamicGainCeiling: OcaDB,
    dynamicGainFloor: OcaDB,
    kneeParameter: OcaFloat32,
    slope: OcaFloat32
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  override open func handleCommand(
    _ command: Ocp1Command,
    from controller: OcaController
  ) async throws -> Ocp1Response {
    switch command.methodID {
    case OcaMethodID("4.27"):
      let parameters: SwiftOCA.OcaDynamics.SetMultipleParameters = try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await setMultiple(
        mask: parameters.mask,
        function: parameters.function,
        threshold: parameters.threshold,
        thresholdPresentationUnits: parameters.thresholdPresentationUnits,
        detectorLaw: parameters.detectorLaw,
        attackTime: parameters.attackTime,
        releaseTime: parameters.releaseTime,
        holdTime: parameters.holdTime,
        dynamicGainCeiling: parameters.dynamicGainCeiling,
        dynamicGainFloor: parameters.dynamicGainFloor,
        kneeParameter: parameters.kneeParameter,
        slope: parameters.slope
      )
      return Ocp1Response()
    default:
      return try await super.handleCommand(command, from: controller)
    }
  }
}

open class OcaDynamicsDetector: OcaActuator {
  override open class var classID: OcaClassID { OcaClassID("1.1.1.15") }
  override open class var classVersion: OcaClassVersionNumber { 3 }

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("4.1"),
    getMethodID: OcaMethodID("4.1"),
    setMethodID: OcaMethodID("4.2")
  )
  public var law: OcaLevelDetectionLaw = .none

  @OcaBoundedDeviceProperty(
    propertyID: OcaPropertyID("4.2"),
    getMethodID: OcaMethodID("4.3"),
    setMethodID: OcaMethodID("4.4")
  )
  public var attackTime = OcaBoundedPropertyValue<OcaTimeInterval>(value: 0, in: 0...1)

  @OcaBoundedDeviceProperty(
    propertyID: OcaPropertyID("4.3"),
    getMethodID: OcaMethodID("4.5"),
    setMethodID: OcaMethodID("4.6")
  )
  public var releaseTime = OcaBoundedPropertyValue<OcaTimeInterval>(value: 0, in: 0...1)

  @OcaBoundedDeviceProperty(
    propertyID: OcaPropertyID("4.4"),
    getMethodID: OcaMethodID("4.7"),
    setMethodID: OcaMethodID("4.8")
  )
  public var holdTime = OcaBoundedPropertyValue<OcaTimeInterval>(value: 0, in: 0...1)

  /// atomic multiple-parameter assignment is device specific; the default implementation
  /// is unimplemented
  open func setMultiple(
    mask: OcaParameterMask,
    law: OcaLevelDetectionLaw,
    attackTime: OcaTimeInterval,
    releaseTime: OcaTimeInterval,
    holdTime: OcaTimeInterval
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  override open func handleCommand(
    _ command: Ocp1Command,
    from controller: OcaController
  ) async throws -> Ocp1Response {
    switch command.methodID {
    case OcaMethodID("4.9"):
      let parameters: SwiftOCA.OcaDynamicsDetector.SetMultipleParameters =
        try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await setMultiple(
        mask: parameters.mask,
        law: parameters.law,
        attackTime: parameters.attackTime,
        releaseTime: parameters.releaseTime,
        holdTime: parameters.holdTime
      )
      return Ocp1Response()
    default:
      return try await super.handleCommand(command, from: controller)
    }
  }
}

open class OcaDynamicsCurve: OcaActuator {
  override open class var classID: OcaClassID { OcaClassID("1.1.1.16") }
  override open class var classVersion: OcaClassVersionNumber { 3 }

  /// the curve is composed of (n + 1) straight line segments joined by (n) knees
  @OcaBoundedDeviceProperty(
    propertyID: OcaPropertyID("4.1"),
    getMethodID: OcaMethodID("4.1"),
    setMethodID: OcaMethodID("4.2")
  )
  public var nSegments = OcaBoundedPropertyValue<OcaUint8>(value: 1, in: 1...8)

  /// segment thresholds; there is no property getter because the limits AES70 returns
  /// from GetThresholds() are scalar rather than per-element
  @OcaDeviceProperty(
    propertyID: OcaPropertyID("4.2"),
    setMethodID: OcaMethodID("4.4")
  )
  public var thresholds: OcaList<OcaDBr> = []

  /// segment slopes; there is no property getter because GetSlopes() returns per-element
  /// limits alongside the value
  @OcaDeviceProperty(
    propertyID: OcaPropertyID("4.3"),
    setMethodID: OcaMethodID("4.6")
  )
  public var slopes: OcaList<OcaFloat32> = []

  /// knee parameters; there is no property getter because GetKneeParameters() returns
  /// per-element limits alongside the value
  @OcaDeviceProperty(
    propertyID: OcaPropertyID("4.4"),
    setMethodID: OcaMethodID("4.8")
  )
  public var kneeParameters: OcaList<OcaFloat32> = []

  @OcaBoundedDeviceProperty(
    propertyID: OcaPropertyID("4.5"),
    getMethodID: OcaMethodID("4.11"),
    setMethodID: OcaMethodID("4.12")
  )
  public var dynamicGainFloor = OcaBoundedPropertyValue<OcaDB>(
    value: -144.0,
    in: -144.0...20.0
  )

  @OcaBoundedDeviceProperty(
    propertyID: OcaPropertyID("4.6"),
    getMethodID: OcaMethodID("4.9"),
    setMethodID: OcaMethodID("4.10")
  )
  public var dynamicGainCeiling = OcaBoundedPropertyValue<OcaDB>(
    value: 0.0,
    in: -144.0...20.0
  )

  /// the limits reported by GetThresholds(); not itself an AES70 property
  open var thresholdRange: ClosedRange<OcaDBz> = -144.0...20.0

  /// the limits reported by GetSlopes(), applied uniformly to every segment; not itself
  /// an AES70 property
  open var slopeRange: ClosedRange<OcaFloat32> = 0...100

  /// the limits reported by GetKneeParameters(), applied uniformly to every segment; not
  /// itself an AES70 property
  open var kneeParameterRange: ClosedRange<OcaFloat32> = 0...1

  /// atomic multiple-parameter assignment is device specific; the default implementation
  /// is unimplemented
  open func setMultiple(
    mask: OcaParameterMask,
    nSegments: OcaUint8,
    thresholds: OcaList<OcaDBr>,
    slopes: OcaList<OcaFloat32>,
    kneeParameters: OcaList<OcaFloat32>,
    dynamicGainFloor: OcaDB,
    dynamicGainCeiling: OcaDB
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  private func _float32ListParameters(
    _ values: OcaList<OcaFloat32>,
    in range: ClosedRange<OcaFloat32>
  ) -> SwiftOCA.OcaDynamicsCurve.GetFloat32ListParameters {
    SwiftOCA.OcaDynamicsCurve.GetFloat32ListParameters(
      values: values,
      minValues: OcaList(repeating: range.lowerBound, count: values.count),
      maxValues: OcaList(repeating: range.upperBound, count: values.count)
    )
  }

  override open func handleCommand(
    _ command: Ocp1Command,
    from controller: OcaController
  ) async throws -> Ocp1Response {
    switch command.methodID {
    case OcaMethodID("4.5"):
      try decodeNullCommand(command)
      try await ensureReadable(by: controller, command: command)
      return try encodeResponse(_float32ListParameters(slopes, in: slopeRange))
    case OcaMethodID("4.7"):
      try decodeNullCommand(command)
      try await ensureReadable(by: controller, command: command)
      return try encodeResponse(
        _float32ListParameters(kneeParameters, in: kneeParameterRange)
      )
    case OcaMethodID("4.13"):
      let parameters: SwiftOCA.OcaDynamicsCurve.SetMultipleParameters =
        try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await setMultiple(
        mask: parameters.mask,
        nSegments: parameters.nSegments,
        thresholds: parameters.thresholds,
        slopes: parameters.slopes,
        kneeParameters: parameters.kneeParameters,
        dynamicGainFloor: parameters.dynamicGainFloor,
        dynamicGainCeiling: parameters.dynamicGainCeiling
      )
      return Ocp1Response()
    case OcaMethodID("4.14"):
      try decodeNullCommand(command)
      try await ensureReadable(by: controller, command: command)
      let parameters = SwiftOCA.OcaDynamicsCurve.GetThresholdsParameters(
        thresholds: thresholds,
        minThreshold: thresholdRange.lowerBound,
        maxThreshold: thresholdRange.upperBound
      )
      return try encodeResponse(parameters)
    default:
      return try await super.handleCommand(command, from: controller)
    }
  }
}
