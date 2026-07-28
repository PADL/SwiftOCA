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

open class OcaFilterClassical: OcaActuator, @unchecked Sendable {
  override open class var classID: OcaClassID { OcaClassID("1.1.1.9") }
  override open class var classVersion: OcaClassVersionNumber { 3 }

  @OcaBoundedProperty(
    propertyID: OcaPropertyID("4.1"),
    getMethodID: OcaMethodID("4.1"),
    setMethodID: OcaMethodID("4.2")
  )
  public var frequency: OcaBoundedProperty<OcaFrequency>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("4.2"),
    getMethodID: OcaMethodID("4.3"),
    setMethodID: OcaMethodID("4.4")
  )
  public var passband: OcaProperty<OcaFilterPassband>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("4.3"),
    getMethodID: OcaMethodID("4.5"),
    setMethodID: OcaMethodID("4.6")
  )
  public var shape: OcaProperty<OcaClassicalFilterShape>.PropertyValue

  @OcaBoundedProperty(
    propertyID: OcaPropertyID("4.4"),
    getMethodID: OcaMethodID("4.7"),
    setMethodID: OcaMethodID("4.8")
  )
  public var order: OcaBoundedProperty<OcaUint16>.PropertyValue

  /// ripple or other shape-dependent parameter; unused by some shapes
  @OcaBoundedProperty(
    propertyID: OcaPropertyID("4.5"),
    getMethodID: OcaMethodID("4.9"),
    setMethodID: OcaMethodID("4.10")
  )
  public var parameter: OcaBoundedProperty<OcaFloat32>.PropertyValue

  @_spi(SwiftOCAPrivate)
  public struct SetMultipleParameters: Ocp1ParametersReflectable {
    public let mask: OcaParameterMask
    public let frequency: OcaFrequency
    public let passband: OcaFilterPassband
    public let shape: OcaClassicalFilterShape
    public let order: OcaUint16
    public let parameter: OcaFloat32

    public init(
      mask: OcaParameterMask,
      frequency: OcaFrequency,
      passband: OcaFilterPassband,
      shape: OcaClassicalFilterShape,
      order: OcaUint16,
      parameter: OcaFloat32
    ) {
      self.mask = mask
      self.frequency = frequency
      self.passband = passband
      self.shape = shape
      self.order = order
      self.parameter = parameter
    }
  }

  /// atomically sets the filter parameters selected by `mask`
  public func setMultiple(
    mask: OcaParameterMask,
    frequency: OcaFrequency,
    passband: OcaFilterPassband,
    shape: OcaClassicalFilterShape,
    order: OcaUint16,
    parameter: OcaFloat32
  ) async throws {
    try await sendCommandRrq(
      methodID: OcaMethodID("4.11"),
      parameters: SetMultipleParameters(
        mask: mask,
        frequency: frequency,
        passband: passband,
        shape: shape,
        order: order,
        parameter: parameter
      )
    )
  }
}

open class OcaFilterParametric: OcaActuator, @unchecked Sendable {
  override open class var classID: OcaClassID { OcaClassID("1.1.1.10") }
  override open class var classVersion: OcaClassVersionNumber { 3 }

  @OcaBoundedProperty(
    propertyID: OcaPropertyID("4.1"),
    getMethodID: OcaMethodID("4.1"),
    setMethodID: OcaMethodID("4.2")
  )
  public var frequency: OcaBoundedProperty<OcaFrequency>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("4.2"),
    getMethodID: OcaMethodID("4.3"),
    setMethodID: OcaMethodID("4.4")
  )
  public var shape: OcaProperty<OcaParametricEQShape>.PropertyValue

  /// the Q of the filter, for conventional parametric implementations
  @OcaBoundedProperty(
    propertyID: OcaPropertyID("4.3"),
    getMethodID: OcaMethodID("4.5"),
    setMethodID: OcaMethodID("4.6")
  )
  public var widthParameter: OcaBoundedProperty<OcaFloat32>.PropertyValue

  @OcaBoundedProperty(
    propertyID: OcaPropertyID("4.4"),
    getMethodID: OcaMethodID("4.7"),
    setMethodID: OcaMethodID("4.8")
  )
  public var inBandGain: OcaBoundedProperty<OcaDB>.PropertyValue

  /// extra shape information, for filter types that require it
  @OcaBoundedProperty(
    propertyID: OcaPropertyID("4.5"),
    getMethodID: OcaMethodID("4.9"),
    setMethodID: OcaMethodID("4.10")
  )
  public var shapeParameter: OcaBoundedProperty<OcaFloat32>.PropertyValue

  @_spi(SwiftOCAPrivate)
  public struct SetMultipleParameters: Ocp1ParametersReflectable {
    public let mask: OcaParameterMask
    public let frequency: OcaFrequency
    public let shape: OcaParametricEQShape
    public let widthParameter: OcaFloat32
    public let inBandGain: OcaDB
    public let shapeParameter: OcaFloat32

    public init(
      mask: OcaParameterMask,
      frequency: OcaFrequency,
      shape: OcaParametricEQShape,
      widthParameter: OcaFloat32,
      inBandGain: OcaDB,
      shapeParameter: OcaFloat32
    ) {
      self.mask = mask
      self.frequency = frequency
      self.shape = shape
      self.widthParameter = widthParameter
      self.inBandGain = inBandGain
      self.shapeParameter = shapeParameter
    }
  }

  /// atomically sets the filter parameters selected by `mask`
  public func setMultiple(
    mask: OcaParameterMask,
    frequency: OcaFrequency,
    shape: OcaParametricEQShape,
    widthParameter: OcaFloat32,
    inBandGain: OcaDB,
    shapeParameter: OcaFloat32
  ) async throws {
    try await sendCommandRrq(
      methodID: OcaMethodID("4.11"),
      parameters: SetMultipleParameters(
        mask: mask,
        frequency: frequency,
        shape: shape,
        widthParameter: widthParameter,
        inBandGain: inBandGain,
        shapeParameter: shapeParameter
      )
    )
  }
}

open class OcaFilterPolynomial: OcaActuator, @unchecked Sendable {
  override open class var classID: OcaClassID { OcaClassID("1.1.1.11") }
  override open class var classVersion: OcaClassVersionNumber { 3 }

  /// numerator coefficients; retrieved together with ``b`` by ``getCoefficients()``
  @OcaProperty(
    propertyID: OcaPropertyID("4.1")
  )
  public var a: OcaProperty<OcaList<OcaFloat32>>.PropertyValue

  /// denominator coefficients; retrieved together with ``a`` by ``getCoefficients()``
  @OcaProperty(
    propertyID: OcaPropertyID("4.2")
  )
  public var b: OcaProperty<OcaList<OcaFloat32>>.PropertyValue

  /// the sampling rate inside the filter, which need not be the device sampling rate
  @OcaBoundedProperty(
    propertyID: OcaPropertyID("4.3"),
    getMethodID: OcaMethodID("4.3"),
    setMethodID: OcaMethodID("4.4")
  )
  public var sampleRate: OcaBoundedProperty<OcaFrequency>.PropertyValue

  /// the maximum number of elements of ``a`` and ``b``
  @OcaProperty(
    propertyID: OcaPropertyID("4.4"),
    getMethodID: OcaMethodID("4.5")
  )
  public var maxOrder: OcaProperty<OcaUint8>.PropertyValue

  @_spi(SwiftOCAPrivate)
  public struct CoefficientsParameters: Ocp1ParametersReflectable {
    public let a: OcaList<OcaFloat32>
    public let b: OcaList<OcaFloat32>

    public init(a: OcaList<OcaFloat32>, b: OcaList<OcaFloat32>) {
      self.a = a
      self.b = b
    }
  }

  public func getCoefficients() async throws
    -> (a: OcaList<OcaFloat32>, b: OcaList<OcaFloat32>)
  {
    let parameters: CoefficientsParameters =
      try await sendCommandRrq(methodID: OcaMethodID("4.1"))
    return (parameters.a, parameters.b)
  }

  public func setCoefficients(a: OcaList<OcaFloat32>, b: OcaList<OcaFloat32>) async throws {
    try await sendCommandRrq(
      methodID: OcaMethodID("4.2"),
      parameters: CoefficientsParameters(a: a, b: b)
    )
  }
}

open class OcaFilterFIR: OcaActuator, @unchecked Sendable {
  override open class var classID: OcaClassID { OcaClassID("1.1.1.12") }
  override open class var classVersion: OcaClassVersionNumber { 3 }

  /// length of the filter in samples
  @OcaBoundedProperty(
    propertyID: OcaPropertyID("4.1"),
    getMethodID: OcaMethodID("4.1")
  )
  public var length: OcaBoundedProperty<OcaUint32>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("4.2"),
    getMethodID: OcaMethodID("4.2"),
    setMethodID: OcaMethodID("4.3")
  )
  public var coefficients: OcaProperty<OcaList<OcaFloat32>>.PropertyValue

  /// the sampling rate inside the filter, which need not be the device sampling rate
  @OcaBoundedProperty(
    propertyID: OcaPropertyID("4.3"),
    getMethodID: OcaMethodID("4.4"),
    setMethodID: OcaMethodID("4.5")
  )
  public var sampleRate: OcaBoundedProperty<OcaFrequency>.PropertyValue
}

open class OcaFilterArbitraryCurve: OcaActuator, @unchecked Sendable {
  override open class var classID: OcaClassID { OcaClassID("1.1.1.13") }
  override open class var classVersion: OcaClassVersionNumber { 3 }

  @OcaProperty(
    propertyID: OcaPropertyID("4.1"),
    getMethodID: OcaMethodID("4.1"),
    setMethodID: OcaMethodID("4.2")
  )
  public var transferFunction: OcaProperty<OcaTransferFunction>.PropertyValue

  /// the sampling rate inside the filter, which need not be the device sampling rate
  @OcaBoundedProperty(
    propertyID: OcaPropertyID("4.2"),
    getMethodID: OcaMethodID("4.3"),
    setMethodID: OcaMethodID("4.4")
  )
  public var sampleRate: OcaBoundedProperty<OcaFrequency>.PropertyValue

  /// minimum number of points the transfer function must specify
  @OcaProperty(
    propertyID: OcaPropertyID("4.3"),
    getMethodID: OcaMethodID("4.5")
  )
  public var tfMinLength: OcaProperty<OcaUint16>.PropertyValue

  /// maximum number of points the transfer function may specify
  @OcaProperty(
    propertyID: OcaPropertyID("4.4"),
    getMethodID: OcaMethodID("4.6")
  )
  public var tfMaxLength: OcaProperty<OcaUint16>.PropertyValue
}
