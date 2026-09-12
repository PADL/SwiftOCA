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

open class OcaDynamics: OcaActuator, @unchecked Sendable {
  override open class var classID: OcaClassID { OcaClassID("1.1.1.14") }
  override open class var classVersion: OcaClassVersionNumber { 3 }

  /// whether the signal level is currently outside the threshold
  @OcaProperty(
    propertyID: OcaPropertyID("4.1"),
    getMethodID: OcaMethodID("4.1")
  )
  public var triggered: OcaProperty<OcaBoolean>.PropertyValue

  /// the instantaneous gain of the dynamics element
  @OcaProperty(
    propertyID: OcaPropertyID("4.2"),
    getMethodID: OcaMethodID("4.2"),
    ocp2GetName: "Gain"
  )
  public var dynamicGain: OcaProperty<OcaDB>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("4.3"),
    getMethodID: OcaMethodID("4.3"),
    setMethodID: OcaMethodID("4.4"),
    ocp2GetName: "Func",
    ocp2SetName: "Func"
  )
  public var function: OcaProperty<OcaDynamicsFunction>.PropertyValue

  @available(*, deprecated, message: "deprecated by AES70, use slope instead")
  @OcaBoundedProperty(
    propertyID: OcaPropertyID("4.4"),
    getMethodID: OcaMethodID("4.5"),
    setMethodID: OcaMethodID("4.6")
  )
  public var ratio: OcaBoundedProperty<OcaFloat32>.PropertyValue

  @OcaBoundedProperty(
    propertyID: OcaPropertyID("4.5"),
    getMethodID: OcaMethodID("4.7"),
    setMethodID: OcaMethodID("4.8")
  )
  public var threshold: OcaBoundedProperty<OcaDBr>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("4.6"),
    getMethodID: OcaMethodID("4.9"),
    setMethodID: OcaMethodID("4.10"),
    ocp2GetName: "Units",
    ocp2SetName: "Units"
  )
  public var thresholdPresentationUnits: OcaProperty<OcaPresentationUnit>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("4.7"),
    getMethodID: OcaMethodID("4.11"),
    setMethodID: OcaMethodID("4.12"),
    ocp2GetName: "Law",
    ocp2SetName: "Law"
  )
  public var detectorLaw: OcaProperty<OcaLevelDetectionLaw>.PropertyValue

  @OcaBoundedProperty(
    propertyID: OcaPropertyID("4.8"),
    getMethodID: OcaMethodID("4.13"),
    setMethodID: OcaMethodID("4.14"),
    ocp2GetName: "Time",
    ocp2SetName: "Time"
  )
  public var attackTime: OcaBoundedProperty<OcaTimeInterval>.PropertyValue

  @OcaBoundedProperty(
    propertyID: OcaPropertyID("4.9"),
    getMethodID: OcaMethodID("4.15"),
    setMethodID: OcaMethodID("4.16"),
    ocp2GetName: "Time",
    ocp2SetName: "Time"
  )
  public var releaseTime: OcaBoundedProperty<OcaTimeInterval>.PropertyValue

  @OcaBoundedProperty(
    propertyID: OcaPropertyID("4.10"),
    getMethodID: OcaMethodID("4.17"),
    setMethodID: OcaMethodID("4.18"),
    ocp2GetName: "Time",
    ocp2SetName: "Time"
  )
  public var holdTime: OcaBoundedProperty<OcaTimeInterval>.PropertyValue

  @OcaBoundedProperty(
    propertyID: OcaPropertyID("4.11"),
    getMethodID: OcaMethodID("4.21"),
    setMethodID: OcaMethodID("4.22"),
    ocp2GetName: "Limit",
    ocp2SetName: "Limit"
  )
  public var dynamicGainCeiling: OcaBoundedProperty<OcaDB>.PropertyValue

  @OcaBoundedProperty(
    propertyID: OcaPropertyID("4.12"),
    getMethodID: OcaMethodID("4.19"),
    setMethodID: OcaMethodID("4.20"),
    ocp2GetName: "Limit",
    ocp2SetName: "Limit"
  )
  public var dynamicGainFloor: OcaBoundedProperty<OcaDB>.PropertyValue

  /// soft knee parameter, interpreted in a device-dependent manner
  @OcaBoundedProperty(
    propertyID: OcaPropertyID("4.13"),
    getMethodID: OcaMethodID("4.23"),
    setMethodID: OcaMethodID("4.24"),
    ocp2GetName: "Parameter",
    ocp2SetName: "Parameter"
  )
  public var kneeParameter: OcaBoundedProperty<OcaFloat32>.PropertyValue

  /// d(output amplitude) / d(input amplitude), independently of ``function``
  @OcaBoundedProperty(
    propertyID: OcaPropertyID("4.14"),
    getMethodID: OcaMethodID("4.25"),
    setMethodID: OcaMethodID("4.26")
  )
  public var slope: OcaBoundedProperty<OcaFloat32>.PropertyValue

  @_spi(SwiftOCAPrivate)
  public struct SetMultipleParameters: OcaParametersReflectable {
    public let mask: OcaParameterMask
    public let function: OcaDynamicsFunction
    public let threshold: OcaDBr
    public let thresholdPresentationUnits: OcaPresentationUnit
    public let detectorLaw: OcaLevelDetectionLaw
    public let attackTime: OcaTimeInterval
    public let releaseTime: OcaTimeInterval
    public let holdTime: OcaTimeInterval
    public let dynamicGainCeiling: OcaDB
    public let dynamicGainFloor: OcaDB
    public let kneeParameter: OcaFloat32
    public let slope: OcaFloat32

    public init(
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
    ) {
      self.mask = mask
      self.function = function
      self.threshold = threshold
      self.thresholdPresentationUnits = thresholdPresentationUnits
      self.detectorLaw = detectorLaw
      self.attackTime = attackTime
      self.releaseTime = releaseTime
      self.holdTime = holdTime
      self.dynamicGainCeiling = dynamicGainCeiling
      self.dynamicGainFloor = dynamicGainFloor
      self.kneeParameter = kneeParameter
      self.slope = slope
    }
  }

  /// atomically sets the dynamics parameters selected by `mask`
  public func setMultiple(
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
    try await sendCommandRrq(
      methodID: OcaMethodID("4.27"),
      parameters: SetMultipleParameters(
        mask: mask,
        function: function,
        threshold: threshold,
        thresholdPresentationUnits: thresholdPresentationUnits,
        detectorLaw: detectorLaw,
        attackTime: attackTime,
        releaseTime: releaseTime,
        holdTime: holdTime,
        dynamicGainCeiling: dynamicGainCeiling,
        dynamicGainFloor: dynamicGainFloor,
        kneeParameter: kneeParameter,
        slope: slope
      )
    )
  }
}

open class OcaDynamicsDetector: OcaActuator, @unchecked Sendable {
  override open class var classID: OcaClassID { OcaClassID("1.1.1.15") }
  override open class var classVersion: OcaClassVersionNumber { 3 }

  @OcaProperty(
    propertyID: OcaPropertyID("4.1"),
    getMethodID: OcaMethodID("4.1"),
    setMethodID: OcaMethodID("4.2")
  )
  public var law: OcaProperty<OcaLevelDetectionLaw>.PropertyValue

  @OcaBoundedProperty(
    propertyID: OcaPropertyID("4.2"),
    getMethodID: OcaMethodID("4.3"),
    setMethodID: OcaMethodID("4.4"),
    ocp2GetName: "Time",
    ocp2SetName: "Time"
  )
  public var attackTime: OcaBoundedProperty<OcaTimeInterval>.PropertyValue

  @OcaBoundedProperty(
    propertyID: OcaPropertyID("4.3"),
    getMethodID: OcaMethodID("4.5"),
    setMethodID: OcaMethodID("4.6"),
    ocp2GetName: "Time",
    ocp2SetName: "Time"
  )
  public var releaseTime: OcaBoundedProperty<OcaTimeInterval>.PropertyValue

  @OcaBoundedProperty(
    propertyID: OcaPropertyID("4.4"),
    getMethodID: OcaMethodID("4.7"),
    setMethodID: OcaMethodID("4.8"),
    ocp2GetName: "Time",
    ocp2SetName: "Time"
  )
  public var holdTime: OcaBoundedProperty<OcaTimeInterval>.PropertyValue

  @_spi(SwiftOCAPrivate)
  public struct SetMultipleParameters: OcaParametersReflectable {
    public let mask: OcaParameterMask
    public let law: OcaLevelDetectionLaw
    public let attackTime: OcaTimeInterval
    public let releaseTime: OcaTimeInterval
    public let holdTime: OcaTimeInterval

    public init(
      mask: OcaParameterMask,
      law: OcaLevelDetectionLaw,
      attackTime: OcaTimeInterval,
      releaseTime: OcaTimeInterval,
      holdTime: OcaTimeInterval
    ) {
      self.mask = mask
      self.law = law
      self.attackTime = attackTime
      self.releaseTime = releaseTime
      self.holdTime = holdTime
    }
  }

  /// atomically sets the detector parameters selected by `mask`
  public func setMultiple(
    mask: OcaParameterMask,
    law: OcaLevelDetectionLaw,
    attackTime: OcaTimeInterval,
    releaseTime: OcaTimeInterval,
    holdTime: OcaTimeInterval
  ) async throws {
    try await sendCommandRrq(
      methodID: OcaMethodID("4.9"),
      parameters: SetMultipleParameters(
        mask: mask,
        law: law,
        attackTime: attackTime,
        releaseTime: releaseTime,
        holdTime: holdTime
      )
    )
  }
}

open class OcaDynamicsCurve: OcaActuator, @unchecked Sendable {
  override open class var classID: OcaClassID { OcaClassID("1.1.1.16") }
  override open class var classVersion: OcaClassVersionNumber { 3 }

  /// the curve is composed of (n + 1) straight line segments joined by (n) knees
  // the 2023 model named this setter's parameter `Slope`, copied from the slope methods,
  // and the getter's bounds `minN`/`maxN`; both are corrected to `NSegments`
  @OcaBoundedProperty(
    propertyID: OcaPropertyID("4.1"),
    getMethodID: OcaMethodID("4.1"),
    setMethodID: OcaMethodID("4.2"),
    ocp2GetName: "NSegments",
    ocp2SetName: "NSegments"
  )
  public var nSegments: OcaBoundedProperty<OcaUint8>.PropertyValue

  /// segment thresholds; the limits are scalar rather than per-element, so the value is
  /// retrieved with ``getThresholds()`` rather than by property accessor
  @OcaProperty(
    propertyID: OcaPropertyID("4.2"),
    setMethodID: OcaMethodID("4.4"),
    ocp2GetName: "Threshold",
    ocp2SetName: "Threshold"
  )
  public var thresholds: OcaProperty<OcaList<OcaDBr>>.PropertyValue

  /// segment slopes; retrieved with ``getSlopes()``, which returns per-element limits
  @OcaProperty(
    propertyID: OcaPropertyID("4.3"),
    setMethodID: OcaMethodID("4.6"),
    ocp2GetName: "Slope",
    ocp2SetName: "Slope"
  )
  public var slopes: OcaProperty<OcaList<OcaFloat32>>.PropertyValue

  /// knee parameters; retrieved with ``getKneeParameters()``, which returns per-element
  /// limits
  @OcaProperty(
    propertyID: OcaPropertyID("4.4"),
    setMethodID: OcaMethodID("4.8"),
    ocp2GetName: "Parameters",
    ocp2SetName: "Parameters"
  )
  public var kneeParameters: OcaProperty<OcaList<OcaFloat32>>.PropertyValue

  @OcaBoundedProperty(
    propertyID: OcaPropertyID("4.5"),
    getMethodID: OcaMethodID("4.11"),
    setMethodID: OcaMethodID("4.12"),
    ocp2GetName: "Gain",
    ocp2SetName: "Gain"
  )
  public var dynamicGainFloor: OcaBoundedProperty<OcaDB>.PropertyValue

  @OcaBoundedProperty(
    propertyID: OcaPropertyID("4.6"),
    getMethodID: OcaMethodID("4.9"),
    setMethodID: OcaMethodID("4.10"),
    ocp2GetName: "Gain",
    ocp2SetName: "Gain"
  )
  public var dynamicGainCeiling: OcaBoundedProperty<OcaDB>.PropertyValue

  @_spi(SwiftOCAPrivate)
  public struct GetThresholdsParameters: OcaParametersReflectable {
    public let thresholds: OcaList<OcaDBr>
    public let minThreshold: OcaDBz
    public let maxThreshold: OcaDBz

    public init(
      thresholds: OcaList<OcaDBr>,
      minThreshold: OcaDBz,
      maxThreshold: OcaDBz
    ) {
      self.thresholds = thresholds
      self.minThreshold = minThreshold
      self.maxThreshold = maxThreshold
    }
  }

  @_spi(SwiftOCAPrivate)
  public struct GetFloat32ListParameters: OcaParametersReflectable {
    public let values: OcaList<OcaFloat32>
    public let minValues: OcaList<OcaFloat32>
    public let maxValues: OcaList<OcaFloat32>

    public init(
      values: OcaList<OcaFloat32>,
      minValues: OcaList<OcaFloat32>,
      maxValues: OcaList<OcaFloat32>
    ) {
      self.values = values
      self.minValues = minValues
      self.maxValues = maxValues
    }
  }

  public func getThresholds() async throws
    -> (thresholds: OcaList<OcaDBr>, minThreshold: OcaDBz, maxThreshold: OcaDBz)
  {
    let parameters: GetThresholdsParameters =
      try await sendCommandRrq(methodID: OcaMethodID("4.14"))
    return (parameters.thresholds, parameters.minThreshold, parameters.maxThreshold)
  }

  public func getSlopes() async throws
    -> (
      slopes: OcaList<OcaFloat32>,
      minSlopes: OcaList<OcaFloat32>,
      maxSlopes: OcaList<OcaFloat32>
    )
  {
    let parameters: GetFloat32ListParameters =
      try await sendCommandRrq(
        methodID: OcaMethodID("4.5"),
        responseNames: ["Slopes", "MinSlope", "MaxSlope"]
      )
    return (parameters.values, parameters.minValues, parameters.maxValues)
  }

  public func getKneeParameters() async throws
    -> (
      kneeParameters: OcaList<OcaFloat32>,
      minKneeParameters: OcaList<OcaFloat32>,
      maxKneeParameters: OcaList<OcaFloat32>
    )
  {
    let parameters: GetFloat32ListParameters =
      try await sendCommandRrq(
        methodID: OcaMethodID("4.7"),
        responseNames: ["Parameters", "MinParameter", "MaxParameter"]
      )
    return (parameters.values, parameters.minValues, parameters.maxValues)
  }

  @_spi(SwiftOCAPrivate)
  public struct SetMultipleParameters: OcaParametersReflectable {
    public let mask: OcaParameterMask
    public let nSegments: OcaUint8
    public let thresholds: OcaList<OcaDBr>
    public let slopes: OcaList<OcaFloat32>
    public let kneeParameters: OcaList<OcaFloat32>
    public let dynamicGainFloor: OcaDB
    public let dynamicGainCeiling: OcaDB

    public init(
      mask: OcaParameterMask,
      nSegments: OcaUint8,
      thresholds: OcaList<OcaDBr>,
      slopes: OcaList<OcaFloat32>,
      kneeParameters: OcaList<OcaFloat32>,
      dynamicGainFloor: OcaDB,
      dynamicGainCeiling: OcaDB
    ) {
      self.mask = mask
      self.nSegments = nSegments
      self.thresholds = thresholds
      self.slopes = slopes
      self.kneeParameters = kneeParameters
      self.dynamicGainFloor = dynamicGainFloor
      self.dynamicGainCeiling = dynamicGainCeiling
    }
  }

  /// atomically sets the curve parameters selected by `mask`
  public func setMultiple(
    mask: OcaParameterMask,
    nSegments: OcaUint8,
    thresholds: OcaList<OcaDBr>,
    slopes: OcaList<OcaFloat32>,
    kneeParameters: OcaList<OcaFloat32>,
    dynamicGainFloor: OcaDB,
    dynamicGainCeiling: OcaDB
  ) async throws {
    try await sendCommandRrq(
      methodID: OcaMethodID("4.13"),
      parameters: SetMultipleParameters(
        mask: mask,
        nSegments: nSegments,
        thresholds: thresholds,
        slopes: slopes,
        kneeParameters: kneeParameters,
        dynamicGainFloor: dynamicGainFloor,
        dynamicGainCeiling: dynamicGainCeiling
      ),
      parameterNames: [
        "Mask",
        "NSegments",
        "Thresholds",
        "Slope",
        "KneeParameter",
        "DynamicGainFloor",
        "DynamicGainCeiling",
      ]
    )
  }
}
