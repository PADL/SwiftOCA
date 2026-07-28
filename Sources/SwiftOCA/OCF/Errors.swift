//
// Copyright (c) 2023-2026 PADL Software Pty Ltd
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

import BinaryParsing

public enum Ocp1Error: Error, Equatable {
  /// An OCA status received from a device; should not be used for local errors
  case status(OcaStatus)
  case exception(Ocp1Notification2ExceptionData)
  case alreadyConnected
  case alreadySubscribedToEvent(OcaEvent)
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
  case deviceAddressChanged
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
  case objectAlreadyContainedByBlock(OcaONo)
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
  case retryOperation
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

extension Ocp1Error {
  /// Runs `body`, translating any `ParsingError` raised by `BinaryParsing` into
  /// the equivalent `Ocp1Error`.
  ///
  /// The builtin PDU decoders throw `Ocp1Error` directly for protocol-level
  /// faults they detect themselves, but bounds violations surface from
  /// `BinaryParsing` as `ParsingError`. Callers up the stack — and the test
  /// suite — match on `Ocp1Error`, so the boundary that hands a PDU to the
  /// parser is responsible for the translation.
  package static func mapping<T>(_ body: () throws -> T) throws -> T {
    do {
      return try body()
    } catch let error as ParsingError {
      if error.status == .insufficientData {
        throw Ocp1Error.pduTooShort
      } else {
        throw Ocp1Error.status(.badFormat)
      }
    }
  }
}
