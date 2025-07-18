//
// Copyright (c) 2023 PADL Software Pty Ltd
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

public enum Ocp1Error: Error, Equatable {
  /// An OCA status received from a device; should not be used for local errors
  case status(OcaStatus)
  case exception(Ocp1Notification2ExceptionData)
  case alreadyConnected
  case alreadySubscribedToEvent
  case arrayOrDataTooBig
  case bonjourRegistrationFailed
  case connectionAlreadyInProgress
  case connectionTimeout
  case datasetAlreadyExists
  case datasetDeviceMismatch
  case datasetMimeTypeMismatch
  case datasetReadFailed
  case datasetWriteFailed
  case datasetTargetMismatch
  case duplicateObject(OcaONo)
  case endpointAlreadyRegistered
  case endpointNotRegistered
  case globalTypeMismatch
  case invalidDatasetFormat
  case invalidDatasetName
  case invalidDatasetONo
  case invalidHandle
  case invalidKeepAlivePdu
  case invalidMessageSize
  case invalidMessageType
  case invalidObject(OcaONo)
  case invalidPduSize
  case invalidProtocolVersion
  case invalidProxyMethodResponse
  case invalidSyncValue
  case missingKeepalive
  case noConnectionDelegate
  case noDatasetStorageProvider
  case noInitialValue
  case noMatchingTypeForClass
  case notConnected
  case notImplemented
  case notSubscribedToEvent
  case objectAlreadyContainedByBlock
  case objectClassIsNotSubclass
  case objectClassMismatch
  case objectNotPresent(OcaONo)
  case pduSendingFailed
  case pduTooShort
  case propertyIsImmutable
  case propertyIsSettableOnly
  case proxyResolutionFailed
  case requestParameterOutOfRange
  case remoteDeviceResolutionFailed
  case responseParameterOutOfRange
  case responseTimeout
  case serviceResolutionFailed
  case unknownDataset
  case unknownDatasetMimeType
  case unknownDatasetVersion
  case unhandledEvent
  case unknownPduType
  case unknownServiceType

  // encoding errors
  case nilNotEncodable
  case stringNotEncodable(String)
  case recursiveTypeDisallowed

  // decoding errors
  case stringNotDecodable([UInt8])
}
