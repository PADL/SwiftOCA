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

open class OcaDataset: OcaRoot, @unchecked
Sendable {
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
    getMethodID: OcaMethodID("2.14"),
    ocp2GetName: "Time"
  )
  public var lastModificationTime: OcaProperty<OcaTime>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("2.6")
  )
  public var maxSize: OcaProperty<OcaUint64>.PropertyValue

  @_spi(SwiftOCAPrivate)
  public struct OpenReadParameters: OcaParametersReflectable {
    public let datasetSize: OcaUint64
    public let handle: OcaIOSessionHandle

    public init(datasetSize: OcaUint64, handle: OcaIOSessionHandle) {
      self.datasetSize = datasetSize
      self.handle = handle
    }
  }

  @_spi(SwiftOCAPrivate) public static let openRead =
    OcaMethodDescriptor<OcaLockState, OpenReadParameters>(
      "2.1",
      name: "OpenRead",
      parameterNames: ["RequestedLockState"]
    )

  public func openRead(lockState: OcaLockState) async throws -> (OcaUint64, OcaIOSessionHandle) {
    let result = try await invoke(Self.openRead, lockState)
    return (result.datasetSize, result.handle)
  }

  @_spi(SwiftOCAPrivate)
  public struct OpenWriteParameters: OcaParametersReflectable {
    public let maxPartSize: OcaUint64
    public let handle: OcaIOSessionHandle

    public init(maxPartSize: OcaUint64, handle: OcaIOSessionHandle) {
      self.maxPartSize = maxPartSize
      self.handle = handle
    }
  }

  @_spi(SwiftOCAPrivate) public static let openWrite =
    OcaMethodDescriptor<OcaLockState, OpenWriteParameters>(
      "2.2",
      name: "OpenWrite",
      parameterNames: ["RequestedLockState"]
    )

  public func openWrite(lockState: OcaLockState) async throws -> (OcaUint64, OcaIOSessionHandle) {
    let result = try await invoke(Self.openWrite, lockState)
    return (result.maxPartSize, result.handle)
  }

  public static let close =
    OcaMethodDescriptor<OcaIOSessionHandle, Void>("2.3", name: "Close", parameterNames: ["Handle"])

  public func close(handle: OcaIOSessionHandle) async throws {
    try await invoke(Self.close, handle)
  }

  @_spi(SwiftOCAPrivate)
  public struct ReadParameters: OcaParametersReflectable {
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
  public struct ReadResultParameters: OcaParametersReflectable {
    public let endOfData: OcaBoolean
    public let part: OcaLongBlob

    public init(endOfData: OcaBoolean, part: OcaLongBlob) {
      self.endOfData = endOfData
      self.part = part
    }
  }

  @_spi(SwiftOCAPrivate) public static let read =
    OcaMethodDescriptor<ReadParameters, ReadResultParameters>("2.4", name: "Read")

  public func read(
    handle: OcaIOSessionHandle,
    position: OcaUint64,
    partSize: OcaUint64
  ) async throws -> (OcaBoolean, OcaLongBlob) {
    let result = try await invoke(
      Self.read,
      .init(handle: handle, position: position, partSize: partSize)
    )
    return (result.endOfData, result.part)
  }

  @_spi(SwiftOCAPrivate)
  public struct WriteParameters: OcaParametersReflectable {
    public let handle: OcaIOSessionHandle
    public let position: OcaUint64
    public let part: OcaLongBlob
  }

  @_spi(SwiftOCAPrivate) public static let write =
    OcaMethodDescriptor<WriteParameters, Void>("2.5", name: "Write")

  public func write(
    handle: OcaIOSessionHandle,
    position: OcaUint64,
    part: OcaLongBlob
  ) async throws {
    try await invoke(Self.write, .init(handle: handle, position: position, part: part))
  }

  public static let clear =
    OcaMethodDescriptor<OcaIOSessionHandle, Void>("2.6", name: "Clear", parameterNames: ["Handle"])

  public func clear(handle: OcaIOSessionHandle) async throws {
    try await invoke(Self.clear, handle)
  }

  @_spi(SwiftOCAPrivate)
  public struct GetDataSetSizesParameters: OcaParametersReflectable {
    public let currentSize: OcaUint64
    public let maxSize: OcaUint64
  }

  @_spi(SwiftOCAPrivate) public static let getDatasetSizes =
    OcaMethodDescriptor<Void, GetDataSetSizesParameters>("2.15", name: "GetDatasetSizes")

  public func getDataSetSizes() async throws -> (OcaUint64, OcaUint64) {
    let result = try await invoke(Self.getDatasetSizes)
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
