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

import Foundation
import SwiftOCA

///
/// Remote proxy represents an individual object on a remote device. This can be used to
/// distribute the object namespace across multiple devices on a board.
///

public class OcaRemoteProxy<T: SwiftOCA.OcaRoot>: OcaRoot {
    private var remoteObject: T
    private var classIdentification: OcaClassIdentification

    override public var objectIdentification: OcaObjectIdentification {
        OcaObjectIdentification(
            oNo: objectNumber,
            classIdentification: classIdentification
        )
    }

    public init(
        object remoteObject: T,
        deviceDelegate: AES70Device? = nil,
        addToRootBlock: Bool = true
    ) async throws {
        self.remoteObject = remoteObject

        var classIdentification = OcaRoot.classIdentification
        try await remoteObject.get(classIdentification: &classIdentification)

        self.classIdentification = classIdentification

        // FIXME: will this have been cached by this point?
        let lockable = remoteObject.lockable.asOptionalResult()
        let role = remoteObject.role.asOptionalResult()

        // FIXME: support overlapping ONo namespaces
        try await super.init(
            objectNumber: remoteObject.objectNumber,
            lockable: lockable.asOptional() ?? false,
            role: role
                .asOptional() ?? "Remote proxy for \(remoteObject.objectNumber)",
            deviceDelegate: deviceDelegate,
            addToRootBlock: addToRootBlock
        )
    }

    override public func handleCommand(
        _ command: Ocp1Command,
        from controller: any AES70Controller
    ) async throws -> Ocp1Response {
        switch command.methodID {
        case OcaMethodID("1.1"): // classIdentification
            fallthrough
        case OcaMethodID("1.2"): // lockable
            fallthrough
        case OcaMethodID("1.5"): // role
            return try await super.handleCommand(command, from: controller)
        default:
            return try await remoteObject.sendCommandRrq(
                methodID: command.methodID,
                parameterCount: command.parameters
                    .parameterCount,
                parameterData: command.parameters
                    .parameterData
            )
        }
    }

    private func forward(event: OcaEvent, eventData data: Data) async throws {
        try await deviceDelegate?.notifySubscribers(
            OcaEvent(emitterONo: objectNumber, eventID: event.eventID),
            parameters: data
        )
    }

    private func subscribe() async throws {
        guard let connectionDelegate = remoteObject.connectionDelegate
        else { throw Ocp1Error.noConnectionDelegate }
        let event = OcaEvent(
            emitterONo: remoteObject.objectNumber,
            eventID: OcaPropertyChangedEventID
        )
        do {
            try await connectionDelegate.addSubscription(event: event, callback: forward)
        } catch Ocp1Error.alreadySubscribedToEvent {
        } catch Ocp1Error.status(.invalidRequest) {}
    }

    private func unsubscribe() async throws {
        guard let connectionDelegate = remoteObject.connectionDelegate
        else { throw Ocp1Error.noConnectionDelegate }
        let event = OcaEvent(emitterONo: objectNumber, eventID: OcaPropertyChangedEventID)
        try await connectionDelegate.removeSubscription(event: event)
    }
    
    deinit {
        Task {
            try? await unsubscribe()
        }
    }
}

private extension Result {
    func asOptional<T>() -> T? where Success == T? {
        switch self {
        case let .success(value):
            guard let value else { return nil }
            return value
        case .failure:
            return nil
        }
    }
}
