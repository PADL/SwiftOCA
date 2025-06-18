//
// Copyright (c) 2025 PADL Software Pty Ltd
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

open class OcaDataset: OcaRoot, @unchecked Sendable {
  override open class var classID: OcaClassID { OcaClassID("1.5") }
  override open class var classVersion: OcaClassVersionNumber { 1 }

  @OcaProperty(
    propertyID: OcaPropertyID("2.1"),
    getMethodID: OcaMethodID("2.7")
  )
  public var owner: OcaProperty<OcaONo>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("2.2"),
    getMethodID: OcaMethodID("2.8"),
    setMethodID: OcaMethodID("2.9")
  )
  public var name: OcaProperty<OcaString>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("2.3"),
    getMethodID: OcaMethodID("2.10"),
    setMethodID: OcaMethodID("2.11")
  )
  public var type: OcaProperty<OcaMimeType>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("2.4"),
    getMethodID: OcaMethodID("2.12"),
    setMethodID: OcaMethodID("2.13")
  )
  public var readOnly: OcaProperty<OcaBoolean>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("2.5"),
    getMethodID: OcaMethodID("2.14")
  )
  public var lastModificationTime: OcaProperty<OcaTime>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("2.6")
  )
  public var maxSize: OcaProperty<OcaUint64>.PropertyValue

  @_spi(SwiftOCAPrivate)
  public struct OpenReadParameters: Ocp1ParametersReflectable {
    public let datasetSize: OcaUint64
    public let handle: OcaIOSessionHandle

    public init(datasetSize: OcaUint64, handle: OcaIOSessionHandle) {
      self.datasetSize = datasetSize
      self.handle = handle
    }
  }

  public func openRead(lockState: OcaLockState) async throws -> (OcaUint64, OcaIOSessionHandle) {
    let result: OpenReadParameters = try await sendCommandRrq(
      methodID: OcaMethodID("2.1"),
      parameters: lockState
    )
    return (result.datasetSize, result.handle)
  }

  @_spi(SwiftOCAPrivate)
  public struct OpenWriteParameters: Ocp1ParametersReflectable {
    public let maxPartSize: OcaUint64
    public let handle: OcaIOSessionHandle

    public init(maxPartSize: OcaUint64, handle: OcaIOSessionHandle) {
      self.maxPartSize = maxPartSize
      self.handle = handle
    }
  }

  public func openWrite(lockState: OcaLockState) async throws -> (OcaUint64, OcaIOSessionHandle) {
    let result: OpenWriteParameters = try await sendCommandRrq(
      methodID: OcaMethodID("2.2"),
      parameters: lockState
    )
    return (result.maxPartSize, result.handle)
  }

  public func close(handle: OcaIOSessionHandle) async throws {
    try await sendCommandRrq(
      methodID: OcaMethodID("2.3"),
      parameters: handle
    )
  }

  @_spi(SwiftOCAPrivate)
  public struct ReadParameters: Ocp1ParametersReflectable {
    public let handle: OcaIOSessionHandle
    public let position: OcaUint64
    public let partSize: OcaUint64

    public init(handle: OcaIOSessionHandle, position: OcaUint64, partSize: OcaUint64) {
      self.handle = handle
      self.position = position
      self.partSize = partSize
    }
  }

  @_spi(SwiftOCAPrivate)
  public struct ReadResultParameters: Ocp1ParametersReflectable {
    public let endOfData: OcaBoolean
    public let part: OcaLongBlob

    public init(endOfData: OcaBoolean, part: OcaLongBlob) {
      self.endOfData = endOfData
      self.part = part
    }
  }

  public func read(
    handle: OcaIOSessionHandle,
    position: OcaUint64,
    partSize: OcaUint64
  ) async throws -> (OcaBoolean, OcaLongBlob) {
    let result: ReadResultParameters = try await sendCommandRrq(
      methodID: OcaMethodID("2.4"),
      parameters: ReadParameters(handle: handle, position: position, partSize: partSize)
    )
    return (result.endOfData, result.part)
  }

  @_spi(SwiftOCAPrivate)
  public struct WriteParameters: Ocp1ParametersReflectable {
    public let handle: OcaIOSessionHandle
    public let position: OcaUint64
    public let part: OcaLongBlob
  }

  public func write(
    handle: OcaIOSessionHandle,
    position: OcaUint64,
    part: OcaLongBlob
  ) async throws {
    try await sendCommandRrq(
      methodID: OcaMethodID("2.5"),
      parameters: WriteParameters(handle: handle, position: position, part: part)
    )
  }

  public func clear(handle: OcaIOSessionHandle) async throws {
    try await sendCommandRrq(
      methodID: OcaMethodID("2.6"),
      parameters: handle
    )
  }

  @_spi(SwiftOCAPrivate)
  public struct GetDataSetSizesParameters: Ocp1ParametersReflectable {
    public let currentSize: OcaUint64
    public let maxSize: OcaUint64
  }

  public func getDataSetSizes() async throws -> (OcaUint64, OcaUint64) {
    let result: GetDataSetSizesParameters = try await sendCommandRrq(methodID: OcaMethodID("2.15"))
    return (result.currentSize, result.maxSize)
  }
}

extension OcaDataset {
  @_spi(SwiftOCAPrivate)
  public func _getOwner(flags: OcaPropertyResolutionFlags = .defaultFlags) async throws
    -> OcaONo
  {
    guard objectNumber != OcaRootBlockONo else { throw Ocp1Error.status(.invalidRequest) }
    return try await $owner._getValue(self, flags: flags)
  }

  func _set(owner: OcaONo) {
    self.$owner.subject.send(.success(owner))
  }
}
