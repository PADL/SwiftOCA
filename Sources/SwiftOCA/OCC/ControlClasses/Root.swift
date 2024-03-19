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

import AsyncExtensions
import Foundation
#if canImport(Combine)
import Combine
#elseif canImport(OpenCombine)
import OpenCombine
#else
protocol ObservableObject {} // placeholder
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif

open class OcaRoot: CustomStringConvertible, ObservableObject, @unchecked
Sendable, OcaKeyPathMarkerProtocol {
    typealias Root = OcaRoot

    public internal(set) weak var connectionDelegate: Ocp1Connection?
    fileprivate var subscriptionCancellable: Ocp1Connection.SubscriptionCancellable?

    // 1.1
    open class var classID: OcaClassID { OcaClassID("1") }
    private var _classID: StaticProperty<OcaClassID> {
        StaticProperty<OcaClassID>(propertyIDs: [OcaPropertyID("1.1")], value: Self.classID)
    }

    // 1.2
    open class var classVersion: OcaClassVersionNumber { 3 }
    private var _classVersion: StaticProperty<OcaClassVersionNumber> {
        StaticProperty<OcaClassVersionNumber>(
            propertyIDs: [OcaPropertyID("1.2")],
            value: Self.classVersion
        )
    }

    public class var classIdentification: OcaClassIdentification {
        OcaClassIdentification(classID: classID, classVersion: classVersion)
    }

    public var objectIdentification: OcaObjectIdentification {
        OcaObjectIdentification(
            oNo: objectNumber,
            classIdentification: Self.classIdentification
        )
    }

    // 1.3
    public let objectNumber: OcaONo
    private var _objectNumber: StaticProperty<OcaONo> {
        StaticProperty<OcaONo>(propertyIDs: [OcaPropertyID("1.3")], value: objectNumber)
    }

    @OcaProperty(
        propertyID: OcaPropertyID("1.4"),
        getMethodID: OcaMethodID("1.2")
    )
    public var lockable: OcaProperty<OcaBoolean>.PropertyValue

    @OcaProperty(
        propertyID: OcaPropertyID("1.5"),
        getMethodID: OcaMethodID("1.5")
    )
    public var role: OcaProperty<OcaString>.PropertyValue

    @OcaProperty(
        propertyID: OcaPropertyID("1.6"),
        getMethodID: OcaMethodID("1.7")
    )
    public var lockState: OcaProperty<OcaLockState>.PropertyValue

    public required init(objectNumber: OcaONo) {
        self.objectNumber = objectNumber
    }

    deinit {
        for (_, keyPath) in allPropertyKeyPaths {
            let value = self[keyPath: keyPath] as! (any OcaPropertySubjectRepresentable)
            value.finish()
        }
    }

    public func getClassIdentification() async throws -> OcaClassIdentification {
        try await sendCommandRrq(methodID: OcaMethodID("1.1"))
    }

    public func lockTotal() async throws {
        try await sendCommandRrq(methodID: OcaMethodID("1.3"))
    }

    public func unlock() async throws {
        try await sendCommandRrq(methodID: OcaMethodID("1.4"))
    }

    public func setLockNoWrite() async throws {
        try await sendCommandRrq(methodID: OcaMethodID("1.6"))
    }

    public var isContainer: Bool {
        false
    }

    public var description: String {
        let objectNumberString = String(format: "0x%08x", objectNumber)

        if case let .success(value) = role {
            return "\(type(of: self))(objectNumber: \(objectNumberString), role: \(value))"
        } else {
            return "\(type(of: self))(objectNumber: \(objectNumberString))"
        }
    }

    private func _getJsonValue(
        flags: _OcaPropertyResolutionFlags = .defaultFlags
    ) async -> [String: Any] {
        var dict = [String: Any]()

        precondition(objectNumber != OcaInvalidONo)

        guard self is OcaWorker else {
            return [:]
        }

        dict[objectNumberJSONKey] = objectNumber
        dict[classIDJSONKey] = Self.classID.description

        for (_, propertyKeyPath) in allPropertyKeyPaths {
            let property =
                self[keyPath: propertyKeyPath] as! (any OcaPropertySubjectRepresentable)
            if let jsonValue = try? await property._getJsonValue(self, flags: flags) {
                dict.merge(jsonValue) { current, _ in current }
            }
        }

        return dict
    }

    open var jsonObject: [String: Any] {
        get async {
            await _getJsonValue()
        }
    }
}

protocol OcaKeyPathMarkerProtocol: AnyObject {}

private extension OcaKeyPathMarkerProtocol where Self: OcaRoot {
    var allKeyPaths: [String: PartialKeyPath<Self>] {
        _allKeyPaths(value: self).reduce(into: [:]) {
            if $1.key.hasPrefix("_") {
                $0[String($1.key.dropFirst())] = $1.value
            }
        }
    }
}

public extension OcaRoot {
    private var staticPropertyKeyPaths: [String: PartialKeyPath<OcaRoot>] {
        ["classID": \._classID,
         "classVersion": \._classVersion,
         "objectNumber": \._objectNumber]
    }

    var allPropertyKeyPaths: [String: PartialKeyPath<OcaRoot>] {
        staticPropertyKeyPaths.merging(
            allKeyPaths.filter { self[keyPath: $0.value] is any OcaPropertySubjectRepresentable },
            uniquingKeysWith: { old, _ in old }
        )
    }

    @Sendable
    private func onPropertyEvent(event: OcaEvent, eventData data: Data) {
        let decoder = Ocp1Decoder()
        guard let propertyID = try? decoder.decode(
            OcaPropertyID.self,
            from: data
        ) else { return }

        allKeyPaths.forEach { _, keyPath in
            if let value = self[keyPath: keyPath] as? (any OcaPropertyChangeEventNotifiable),
               value.propertyIDs.contains(propertyID)
            {
                try? value.onEvent(self, event: event, eventData: data)
                return
            }
        }
    }

    func subscribe() async throws {
        guard subscriptionCancellable == nil else { return } // already subscribed
        guard let connectionDelegate else { throw Ocp1Error.noConnectionDelegate }
        let event = OcaEvent(emitterONo: objectNumber, eventID: OcaPropertyChangedEventID)
        do {
            subscriptionCancellable = try await connectionDelegate.addSubscription(
                event: event,
                callback: onPropertyEvent
            )
        } catch Ocp1Error.alreadySubscribedToEvent {
        } catch Ocp1Error.status(.invalidRequest) {
            // FIXME: in our device implementation not all properties can be subcribed to
        }
    }

    func unsubscribe() async throws {
        guard let subscriptionCancellable else { throw Ocp1Error.notSubscribedToEvent }
        guard let connectionDelegate else { throw Ocp1Error.noConnectionDelegate }
        try await connectionDelegate.removeSubscription(subscriptionCancellable)
    }

    func refreshAll() async {
        for (_, keyPath) in allPropertyKeyPaths {
            let property = (self[keyPath: keyPath] as! any OcaPropertyRepresentable)
            await property.refresh(self)
        }
    }

    func refresh() async {
        for (_, keyPath) in allPropertyKeyPaths {
            let property = (self[keyPath: keyPath] as! any OcaPropertyRepresentable)
            if property.hasValueOrError {
                await property.refresh(self)
            }
        }
    }

    internal var isSubscribed: Bool {
        get async throws {
            guard let connectionDelegate else { throw Ocp1Error.noConnectionDelegate }
            let event = OcaEvent(emitterONo: objectNumber, eventID: OcaPropertyChangedEventID)
            return await connectionDelegate.isSubscribed(event: event)
        }
    }

    internal struct StaticProperty<T: Codable & Sendable>: OcaPropertySubjectRepresentable {
        typealias Value = T

        var propertyIDs: [OcaPropertyID]
        var value: T

        func refresh(_ object: SwiftOCA.OcaRoot) async {}
        func subscribe(_ object: OcaRoot) async {}

        var description: String {
            String(describing: value)
        }

        var currentValue: OcaProperty<Value>.PropertyValue {
            OcaProperty<Value>.PropertyValue.success(value)
        }

        var subject: AsyncCurrentValueSubject<PropertyValue> {
            AsyncCurrentValueSubject(currentValue)
        }

        #if canImport(SwiftUI)
        var binding: Binding<PropertyValue> {
            Binding(
                get: {
                    currentValue
                },
                set: { _ in
                }
            )
        }
        #endif

        @_spi(SwiftOCAPrivate) @discardableResult
        public func _getValue(
            _ object: OcaRoot,
            flags: _OcaPropertyResolutionFlags
        ) async throws -> Value {
            value
        }

        @_spi(SwiftOCAPrivate)
        public func _getJsonValue(
            _ object: OcaRoot,
            flags: _OcaPropertyResolutionFlags = .defaultFlags
        ) async throws -> [String: Any] {
            let value = try await _getValue(object, flags: flags)
            let jsonValue: Any

            if JSONSerialization.isValidJSONObject(value) {
                jsonValue = value
            } else {
                jsonValue = try JSONEncoder().reencodeAsValidJSONObject(value)
            }
            return [propertyIDs[0].description: jsonValue]
        }
    }
}

extension OcaRoot: Equatable {
    public static func == (lhs: OcaRoot, rhs: OcaRoot) -> Bool {
        lhs.connectionDelegate == rhs.connectionDelegate &&
            lhs.objectNumber == rhs.objectNumber
    }
}

extension OcaRoot: Hashable {
    public func hash(into hasher: inout Hasher) {
        connectionDelegate?.hash(into: &hasher)
        hasher.combine(objectNumber)
    }
}

public struct OcaGetPathParameters: Ocp1ParametersReflectable {
    public var namePath: OcaNamePath
    public var oNoPath: OcaONoPath

    public init(namePath: OcaNamePath, oNoPath: OcaONoPath) {
        self.namePath = namePath
        self.oNoPath = oNoPath
    }
}

extension OcaRoot {
    func getPath(methodID: OcaMethodID) async throws -> (OcaNamePath, OcaONoPath) {
        let responseParams: OcaGetPathParameters
        responseParams = try await sendCommandRrq(methodID: methodID)
        return (responseParams.namePath, responseParams.oNoPath)
    }
}

public struct OcaGetPortNameParameters: Ocp1ParametersReflectable {
    public let portID: OcaPortID

    public init(portID: OcaPortID) {
        self.portID = portID
    }
}

public struct OcaSetPortNameParameters: Ocp1ParametersReflectable {
    public let portID: OcaPortID
    public let name: OcaString

    public init(portID: OcaPortID, name: OcaString) {
        self.portID = portID
        self.name = name
    }
}

public protocol OcaOwnable: OcaRoot {
    var owner: OcaProperty<OcaONo>.PropertyValue { get set }

    var path: (OcaNamePath, OcaONoPath) { get async throws }
}
