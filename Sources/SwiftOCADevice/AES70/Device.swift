//
//  Device.swift
//
//  Copyright (c) 2022 Simon Whitty. All rights reserved.
//  Portions Copyright (c) 2023 PADL Software Pty Ltd. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

@_spi(Private) @_implementationOnly
import func FlyingSocks.withThrowingTimeout
import Foundation
import SwiftOCA

public protocol AES70Device: Actor {
    var rootBlock: OcaBlock<OcaRoot>! { get }
    var subscriptionManager: OcaSubscriptionManager! { get }
    var deviceManager: OcaDeviceManager! { get }

    var objects: [OcaONo: OcaRoot] { get }

    func register(
        object: OcaRoot,
        addToRootBlock: Bool
    ) throws

    func allocateObjectNumber() -> OcaONo

    func notifySubscribers(
        _ event: OcaEvent,
        parameters: Data
    ) async throws
}

protocol AES70DevicePrivate: AES70Device {
    var objects: [OcaONo: OcaRoot] { get set }
}

public extension AES70Device {
    func notifySubscribers(_ event: OcaEvent) async throws {
        try await notifySubscribers(event, parameters: Data())
    }

    func register(object: OcaRoot) throws {
        try register(object: object, addToRootBlock: true)
    }
}

extension AES70DevicePrivate {
    public func register(object: OcaRoot, addToRootBlock: Bool = true) throws {
        precondition(
            object.objectNumber != OcaInvalidONo,
            "cannot register object with invalid ONo"
        )
        guard objects[object.objectNumber] == nil else {
            throw Ocp1Error.status(.badONo)
        }
        objects[object.objectNumber] = object
        if addToRootBlock {
            precondition(object.objectNumber != OcaRootBlockONo)
            try rootBlock.add(member: object)
        }
    }

    func handleCommand(
        _ command: Ocp1Command,
        timeout: TimeInterval? = nil,
        from controller: any AES70Controller
    ) async -> Ocp1Response {
        do {
            let object = objects[command.targetONo]
            guard let object else {
                throw Ocp1Error.status(.badONo)
            }

            if let timeout {
                return try await withThrowingTimeout(seconds: timeout) {
                    try await object.handleCommand(command, from: controller)
                }
            } else {
                return try await object.handleCommand(command, from: controller)
            }
        } catch let Ocp1Error.status(status) {
            return .init(responseSize: 0, handle: command.handle, statusCode: status)
        } catch {
            return .init(responseSize: 0, handle: command.handle, statusCode: .deviceError)
        }
    }
}
