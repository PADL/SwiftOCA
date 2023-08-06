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

import AsyncAlgorithms
import Foundation

public class AES70OCP1SPIConnection: AES70OCP1Connection {
    fileprivate let device: String
    fileprivate var fileDescriptor: Int32 = -1
    fileprivate var channel: DispatchIO?
    fileprivate let queue = DispatchQueue.global(qos: .userInitiated)

    public init(
        device: String = "/dev/spidev0.0"
    ) {
        assert(device.hasPrefix("/dev/"))
        self.device = String(device.dropFirst(5))

        super.init(options: AES70OCP1ConnectionOptions())
    }

    private func closeChannel() {
        if let channel {
            channel.close()
            self.channel = nil
        }
    }

    deinit {
        Task {
            await closeChannel()
        }
    }

    override func connectDevice() async throws {
        let fileDescriptor = open("/dev/\(device)", O_RDWR)
        if fileDescriptor < 0 {
            throw Ocp1Error.notConnected
        }

        precondition(channel == nil)
        channel = DispatchIO(
            type: .stream,
            fileDescriptor: fileDescriptor,
            queue: queue,
            cleanupHandler: { fileDescriptor in
                close(fileDescriptor)
            }
        )
        guard let channel else {
            throw Ocp1Error.notConnected
        }
        channel.setLimit(lowWater: .max)

        try await super.connectDevice()
    }

    override public func disconnectDevice(clearObjectCache: Bool) async throws {
        closeChannel()
        try await super.disconnectDevice(clearObjectCache: clearObjectCache)
    }

    override public func read(_ length: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            guard let channel else {
                continuation.resume(throwing: Ocp1Error.notConnected)
                return
            }

            channel.read(offset: 0, length: length, queue: queue, ioHandler: { _, data, error in
                if let data {
                    continuation.resume(returning: Data(copying: data))
                } else if error != 0 {
                    continuation.resume(throwing: Ocp1Error.pduTooShort)
                } else {
                    continuation.resume(throwing: Ocp1Error.notConnected)
                }
            })
        }
    }

    override public func write(_ data: Data) async throws -> Int {
        try await withCheckedThrowingContinuation { continuation in
            guard let channel else {
                continuation.resume(throwing: Ocp1Error.notConnected)
                return
            }

            channel.write(
                offset: 0,
                data: data.dispatchData,
                queue: queue,
                ioHandler: { done, _, error in
                    guard done else {
                        return
                    }
                    if error == 0 {
                        continuation.resume(returning: data.count)
                    } else {
                        continuation.resume(throwing: Ocp1Error.pduSendingFailed)
                    }
                }
            )
        }
    }

    override public var connectionPrefix: String {
        OcaSpiConnectionPrefix + "/" + device
    }
}

public class AES70OCP1BrooklynSPIConnection: AES70OCP1SPIConnection {
    private static let Sentinel = Data([0x44, 0x4E, 0x54, 0x45])

    private let pipeID: UInt8
    private var receivedDataChannel = AsyncChannel<Data>()
    private var receivedData = Data()

    public init(
        pipeID: UInt8,
        device: String = "/dev/spidev0.0"
    ) {
        self.pipeID = pipeID
        super.init(device: device)

        Task {
            repeat {
                do {
                    let frame = try await super.read(8)
                    guard frame.prefix(4) == Self.Sentinel else {
                        throw Ocp1Error.invalidSyncValue
                    }
                    let frameLength: UInt16 = frame.decodeInteger(index: 4)
                    let bytesToRead: UInt16 = frameLength + (frameLength + 4) & ~3
                    await receivedDataChannel.send(try await super.read(Int(bytesToRead)))
                } catch {
                    break
                }
            } while !Task.isCancelled
        }
    }

    deinit {
        receivedDataChannel.finish()
    }

    private func drainChannel(atLeast length: Int) async {
        guard receivedData.count < length else { return }

        for await data in receivedDataChannel {
            receivedData += data
            guard receivedData.count < length else { return }
        }
    }

    override public func read(_ length: Int) async throws -> Data {
        while receivedData.count < length {
            await drainChannel(atLeast: length)
        }

        // NOTE: make a copy here, otherwise we will have concurrent access
        let data = Data(receivedData.prefix(length))
        receivedData = receivedData.dropFirst(length)

        return data
    }

    override public func write(_ data: Data) async throws -> Int {
        var frame = Self.Sentinel

        frame.encodeInteger(UInt16(data.count), index: 4)
        frame += [0, pipeID]
        frame += data
        frame.pad(toLength: (frame.count + 4) & ~3, with: 0)

        return try await super.write(frame)
    }

    override public var connectionPrefix: String {
        super.connectionPrefix + "/pipe\(pipeID)"
    }
}

private extension Data {
    init(copying dispatchData: DispatchData) {
        var result = Data(count: dispatchData.count)
        result.withUnsafeMutableBytes {
            _ = dispatchData.copyBytes(to: $0)
        }
        self = result
    }

    var dispatchData: DispatchData {
        withUnsafeBytes {
            DispatchData(bytes: $0)
        }
    }

    mutating func pad(toLength count: Int, with element: Element) {
        append(contentsOf: repeatElement(element, count: Swift.max(0, count - self.count)))
    }
}
