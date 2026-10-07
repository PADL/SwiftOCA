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

@OcaClass
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

  public struct OpenReadParameters: OcaParametersReflectable {
    public let datasetSize: OcaUint64
    public let handle: OcaIOSessionHandle

    public init(datasetSize: OcaUint64, handle: OcaIOSessionHandle) {
      self.datasetSize = datasetSize
      self.handle = handle
    }
  }

  @OcaMethod("2.1", name: "OpenRead", parameterNames: ["RequestedLockState"])
  public func openRead(requestedLockState: OcaLockState) async throws -> OpenReadParameters

  public struct OpenWriteParameters: OcaParametersReflectable {
    public let maxPartSize: OcaUint64
    public let handle: OcaIOSessionHandle

    public init(maxPartSize: OcaUint64, handle: OcaIOSessionHandle) {
      self.maxPartSize = maxPartSize
      self.handle = handle
    }
  }

  @OcaMethod("2.2", name: "OpenWrite", parameterNames: ["RequestedLockState"])
  public func openWrite(requestedLockState: OcaLockState) async throws -> OpenWriteParameters

  @OcaMethod("2.3", name: "Close", parameterNames: ["Handle"])
  public func close(handle: OcaIOSessionHandle) async throws

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

  public struct ReadResultParameters: OcaParametersReflectable {
    public let endOfData: OcaBoolean
    public let part: OcaLongBlob

    public init(endOfData: OcaBoolean, part: OcaLongBlob) {
      self.endOfData = endOfData
      self.part = part
    }
  }

  @OcaMethod("2.4", name: "Read", parameters: ReadParameters.self)
  public func read(
    handle: OcaIOSessionHandle,
    position: OcaUint64,
    partSize: OcaUint64
  ) async throws -> ReadResultParameters

  public struct WriteParameters: OcaParametersReflectable {
    public let handle: OcaIOSessionHandle
    public let position: OcaUint64
    public let part: OcaLongBlob
  }

  @OcaMethod("2.5", name: "Write", parameters: WriteParameters.self)
  public func write(
    handle: OcaIOSessionHandle,
    position: OcaUint64,
    part: OcaLongBlob
  ) async throws

  @OcaMethod("2.6", name: "Clear", parameterNames: ["Handle"])
  public func clear(handle: OcaIOSessionHandle) async throws

  public struct GetDataSetSizesParameters: OcaParametersReflectable {
    public let currentSize: OcaUint64
    public let maxSize: OcaUint64
  }

  @OcaMethod("2.15", name: "GetDatasetSizes")
  public func getDatasetSizes() async throws -> GetDataSetSizesParameters
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
