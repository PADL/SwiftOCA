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
    case alreadySubscribedToEvent
    case arrayOrDataTooBig
    case bonjourRegistrationFailed
    case connectionTimeout
    case endpointAlreadyRegistered
    case endpointNotRegistered
    case invalidHandle
    case invalidKeepAlivePdu
    case invalidMessageSize
    case invalidMessageType
    case invalidPduSize
    case invalidProtocolVersion
    case invalidSyncValue
    case noConnectionDelegate
    case noInitialValue
    case notConnected
    case notImplemented
    case objectAlreadyContainedByBlock
    case objectClassMismatch
    case objectNotPresent
    case pduSendingFailed
    case pduTooShort
    case propertyIsImmutable
    case proxyResolutionFailed
    case requestParameterOutOfRange
    case remoteDeviceResolutionFailed
    case responseParameterOutOfRange
    case responseTimeout
    case serviceResolutionFailed
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
