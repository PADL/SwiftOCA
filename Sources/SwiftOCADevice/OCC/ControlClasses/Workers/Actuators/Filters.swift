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

open class OcaFilterClassical: OcaActuator {
  override open class var classID: OcaClassID { OcaClassID("1.1.1.9") }
  override open class var classVersion: OcaClassVersionNumber { 3 }

  @OcaBoundedDeviceProperty(
    propertyID: OcaPropertyID("4.1"),
    getMethodID: OcaMethodID("4.1"),
    setMethodID: OcaMethodID("4.2")
  )
  public var frequency = OcaBoundedPropertyValue<OcaFrequency>(value: 1000, in: 10...20000)

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("4.2"),
    getMethodID: OcaMethodID("4.3"),
    setMethodID: OcaMethodID("4.4")
  )
  public var passband: OcaFilterPassband = .lowPass

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("4.3"),
    getMethodID: OcaMethodID("4.5"),
    setMethodID: OcaMethodID("4.6")
  )
  public var shape: OcaClassicalFilterShape = .butterworth

  @OcaBoundedDeviceProperty(
    propertyID: OcaPropertyID("4.4"),
    getMethodID: OcaMethodID("4.7"),
    setMethodID: OcaMethodID("4.8")
  )
  public var order = OcaBoundedPropertyValue<OcaUint16>(value: 1, in: 1...8)

  /// ripple or other shape-dependent parameter; unused by some shapes
  @OcaBoundedDeviceProperty(
    propertyID: OcaPropertyID("4.5"),
    getMethodID: OcaMethodID("4.9"),
    setMethodID: OcaMethodID("4.10")
  )
  public var parameter = OcaBoundedPropertyValue<OcaFloat32>(value: 0, in: 0...1)

  /// atomic multiple-parameter assignment is device specific; the default implementation
  /// is unimplemented
  open func setMultiple(
    mask: OcaParameterMask,
    frequency: OcaFrequency,
    passband: OcaFilterPassband,
    shape: OcaClassicalFilterShape,
    order: OcaUint16,
    parameter: OcaFloat32
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  override open func handleCommand(
    _ command: Ocp1Command,
    from controller: OcaController
  ) async throws -> Ocp1Response {
    switch command.methodID {
    case OcaMethodID("4.11"):
      let parameters: SwiftOCA.OcaFilterClassical.SetMultipleParameters =
        try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await setMultiple(
        mask: parameters.mask,
        frequency: parameters.frequency,
        passband: parameters.passband,
        shape: parameters.shape,
        order: parameters.order,
        parameter: parameters.parameter
      )
      return Ocp1Response()
    default:
      return try await super.handleCommand(command, from: controller)
    }
  }
}

open class OcaFilterParametric: OcaActuator {
  override open class var classID: OcaClassID { OcaClassID("1.1.1.10") }
  override open class var classVersion: OcaClassVersionNumber { 3 }

  @OcaBoundedDeviceProperty(
    propertyID: OcaPropertyID("4.1"),
    getMethodID: OcaMethodID("4.1"),
    setMethodID: OcaMethodID("4.2")
  )
  public var frequency = OcaBoundedPropertyValue<OcaFrequency>(value: 1000, in: 10...20000)

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("4.2"),
    getMethodID: OcaMethodID("4.3"),
    setMethodID: OcaMethodID("4.4")
  )
  public var shape: OcaParametricEQShape = .none

  /// the Q of the filter, for conventional parametric implementations
  @OcaBoundedDeviceProperty(
    propertyID: OcaPropertyID("4.3"),
    getMethodID: OcaMethodID("4.5"),
    setMethodID: OcaMethodID("4.6")
  )
  public var widthParameter = OcaBoundedPropertyValue<OcaFloat32>(value: 1, in: 0.1...100)

  @OcaBoundedDeviceProperty(
    propertyID: OcaPropertyID("4.4"),
    getMethodID: OcaMethodID("4.7"),
    setMethodID: OcaMethodID("4.8")
  )
  public var inBandGain = OcaBoundedPropertyValue<OcaDB>(value: 0.0, in: -144.0...20.0)

  /// extra shape information, for filter types that require it
  @OcaBoundedDeviceProperty(
    propertyID: OcaPropertyID("4.5"),
    getMethodID: OcaMethodID("4.9"),
    setMethodID: OcaMethodID("4.10")
  )
  public var shapeParameter = OcaBoundedPropertyValue<OcaFloat32>(value: 0, in: 0...1)

  /// atomic multiple-parameter assignment is device specific; the default implementation
  /// is unimplemented
  open func setMultiple(
    mask: OcaParameterMask,
    frequency: OcaFrequency,
    shape: OcaParametricEQShape,
    widthParameter: OcaFloat32,
    inBandGain: OcaDB,
    shapeParameter: OcaFloat32
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  override open func handleCommand(
    _ command: Ocp1Command,
    from controller: OcaController
  ) async throws -> Ocp1Response {
    switch command.methodID {
    case OcaMethodID("4.11"):
      let parameters: SwiftOCA.OcaFilterParametric.SetMultipleParameters =
        try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await setMultiple(
        mask: parameters.mask,
        frequency: parameters.frequency,
        shape: parameters.shape,
        widthParameter: parameters.widthParameter,
        inBandGain: parameters.inBandGain,
        shapeParameter: parameters.shapeParameter
      )
      return Ocp1Response()
    default:
      return try await super.handleCommand(command, from: controller)
    }
  }
}

open class OcaFilterPolynomial: OcaActuator {
  override open class var classID: OcaClassID { OcaClassID("1.1.1.11") }
  override open class var classVersion: OcaClassVersionNumber { 3 }

  /// numerator coefficients; there is no property accessor because AES70 returns this
  /// together with ``b`` from GetCoefficients()
  @OcaDeviceProperty(
    propertyID: OcaPropertyID("4.1")
  )
  public var a: OcaList<OcaFloat32> = []

  /// denominator coefficients; there is no property accessor because AES70 returns this
  /// together with ``a`` from GetCoefficients()
  @OcaDeviceProperty(
    propertyID: OcaPropertyID("4.2")
  )
  public var b: OcaList<OcaFloat32> = []

  /// the sampling rate inside the filter, which need not be the device sampling rate
  @OcaBoundedDeviceProperty(
    propertyID: OcaPropertyID("4.3"),
    getMethodID: OcaMethodID("4.3"),
    setMethodID: OcaMethodID("4.4")
  )
  public var sampleRate = OcaBoundedPropertyValue<OcaFrequency>(
    value: 48000,
    in: 8000...192_000
  )

  /// the maximum number of elements of ``a`` and ``b``
  @OcaDeviceProperty(
    propertyID: OcaPropertyID("4.4"),
    getMethodID: OcaMethodID("4.5")
  )
  public var maxOrder: OcaUint8 = 0

  open func set(a: OcaList<OcaFloat32>, b: OcaList<OcaFloat32>) async throws {
    guard a.count <= Int(maxOrder), b.count <= Int(maxOrder) else {
      throw Ocp1Error.status(.parameterOutOfRange)
    }
    self.a = a
    self.b = b
  }

  override open func handleCommand(
    _ command: Ocp1Command,
    from controller: OcaController
  ) async throws -> Ocp1Response {
    switch command.methodID {
    case OcaMethodID("4.1"):
      try decodeNullCommand(command)
      try await ensureReadable(by: controller, command: command)
      let parameters = SwiftOCA.OcaFilterPolynomial.CoefficientsParameters(a: a, b: b)
      return try encodeResponse(parameters)
    case OcaMethodID("4.2"):
      let parameters: SwiftOCA.OcaFilterPolynomial.CoefficientsParameters =
        try decodeCommand(command)
      try await ensureWritable(by: controller, command: command)
      try await set(a: parameters.a, b: parameters.b)
      return Ocp1Response()
    default:
      return try await super.handleCommand(command, from: controller)
    }
  }
}

open class OcaFilterFIR: OcaActuator {
  override open class var classID: OcaClassID { OcaClassID("1.1.1.12") }
  override open class var classVersion: OcaClassVersionNumber { 3 }

  /// length of the filter in samples
  @OcaBoundedDeviceProperty(
    propertyID: OcaPropertyID("4.1"),
    getMethodID: OcaMethodID("4.1")
  )
  public var length = OcaBoundedPropertyValue<OcaUint32>(value: 0, in: 0...0)

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("4.2"),
    getMethodID: OcaMethodID("4.2"),
    setMethodID: OcaMethodID("4.3")
  )
  public var coefficients: OcaList<OcaFloat32> = []

  /// the sampling rate inside the filter, which need not be the device sampling rate
  @OcaBoundedDeviceProperty(
    propertyID: OcaPropertyID("4.3"),
    getMethodID: OcaMethodID("4.4"),
    setMethodID: OcaMethodID("4.5")
  )
  public var sampleRate = OcaBoundedPropertyValue<OcaFrequency>(
    value: 48000,
    in: 8000...192_000
  )
}

open class OcaFilterArbitraryCurve: OcaActuator {
  override open class var classID: OcaClassID { OcaClassID("1.1.1.13") }
  override open class var classVersion: OcaClassVersionNumber { 3 }

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("4.1"),
    getMethodID: OcaMethodID("4.1"),
    setMethodID: OcaMethodID("4.2")
  )
  public var transferFunction = OcaTransferFunction()

  /// the sampling rate inside the filter, which need not be the device sampling rate
  @OcaBoundedDeviceProperty(
    propertyID: OcaPropertyID("4.2"),
    getMethodID: OcaMethodID("4.3"),
    setMethodID: OcaMethodID("4.4")
  )
  public var sampleRate = OcaBoundedPropertyValue<OcaFrequency>(
    value: 48000,
    in: 8000...192_000
  )

  /// minimum number of points the transfer function must specify
  @OcaDeviceProperty(
    propertyID: OcaPropertyID("4.3"),
    getMethodID: OcaMethodID("4.5")
  )
  public var tfMinLength: OcaUint16 = 0

  /// maximum number of points the transfer function may specify
  @OcaDeviceProperty(
    propertyID: OcaPropertyID("4.4"),
    getMethodID: OcaMethodID("4.6")
  )
  public var tfMaxLength: OcaUint16 = 0
}
