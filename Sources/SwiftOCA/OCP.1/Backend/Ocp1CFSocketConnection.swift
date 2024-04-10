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

#if canImport(CoreFoundation)

import AsyncAlgorithms
@_implementationOnly
@preconcurrency
import CoreFoundation
import Foundation

private func Ocp1CFSocketConnection_DataCallBack(
    _ socket: CFSocket?,
    _ type: CFSocketCallBackType,
    _ address: CFData?,
    _ data: UnsafeRawPointer?,
    _ info: UnsafeMutableRawPointer?
) {
    guard let info else { return }
    let connection = Unmanaged<Ocp1CFSocketConnection>.fromOpaque(info).takeUnretainedValue()
    connection.dataCallBack(socket, type, address, data)
}

extension CFSocket: @unchecked
Sendable {}

public class Ocp1CFSocketConnection: Ocp1Connection {
    fileprivate let deviceAddress: Data
    fileprivate var cfSocket: CFSocket?
    fileprivate var type: Int32 {
        fatalError("must be implemented by subclass")
    }

    private var receivedDataChannel = AsyncChannel<Data>()
    private var receivedData = Data()

    public init(
        deviceAddress: Data,
        options: Ocp1ConnectionOptions = Ocp1ConnectionOptions()
    ) {
        self.deviceAddress = deviceAddress
        super.init(options: options)
    }

    deinit {
        if let cfSocket {
            CFSocketInvalidate(cfSocket)
        }
        receivedDataChannel.finish()
    }

    fileprivate nonisolated func dataCallBack(
        _ socket: CFSocket?,
        _ type: CFSocketCallBackType,
        _ address: CFData?,
        _ cfData: UnsafeRawPointer?
    ) {
        precondition(Thread.isMainThread)

        guard let cfData else { return }
        let data = Unmanaged<CFData>.fromOpaque(cfData).takeUnretainedValue().data
        guard data.count > 0 else { return }

        Task {
            await receivedDataChannel.send(data)
        }
    }

    override func connectDevice() async throws {
        var context = CFSocketContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        let cfSocket = CFSocketCreate(
            kCFAllocatorDefault,
            AF_INET,
            type,
            isStreamType(type) ? Int32(IPPROTO_TCP) : Int32(IPPROTO_UDP),
            CFSocketCallBackType.dataCallBack.rawValue,
            Ocp1CFSocketConnection_DataCallBack,
            &context
        )

        var options = CFSocketGetSocketFlags(cfSocket)
        options |= kCFSocketCloseOnInvalidate
        CFSocketSetSocketFlags(cfSocket, options)

        var yes: CInt = 1
        setsockopt(
            CFSocketGetNative(cfSocket),
            SOL_SOCKET,
            SO_REUSEADDR,
            &yes,
            socklen_t(CInt.Stride())
        )
        setsockopt(
            CFSocketGetNative(cfSocket),
            SOL_SOCKET,
            SO_REUSEPORT,
            &yes,
            socklen_t(CInt.Stride())
        )

        self.cfSocket = cfSocket

        let runLoopSource = CFSocketCreateRunLoopSource(kCFAllocatorDefault, cfSocket, 0)

        try await withTaskCancellationHandler(operation: {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, CFRunLoopMode.defaultMode)
            guard CFSocketIsValid(cfSocket),
                  CFSocketConnectToAddress(cfSocket, deviceAddress.cfData, 0) == .success
            else {
                throw Ocp1Error.notConnected
            }
        }, onCancel: {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, CFRunLoopMode.defaultMode)
        })

        try await super.connectDevice()
    }

    override public func disconnectDevice(clearObjectCache: Bool) async throws {
        if let cfSocket {
            CFSocketInvalidate(cfSocket)
            self.cfSocket = nil
        }

        try await super.disconnectDevice(clearObjectCache: clearObjectCache)
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
        guard let cfSocket else {
            throw Ocp1Error.notConnected
        }
        let result = CFSocketSendData(cfSocket, nil, data.cfData, 0)
        switch result {
        case .success:
            return data.count
        case .timeout:
            throw Ocp1Error.responseTimeout
        case .error:
            fallthrough
        default:
            throw Ocp1Error.pduSendingFailed
        }
    }
}

public final class Ocp1CFSocketUDPConnection: Ocp1CFSocketConnection {
    override public var heartbeatTime: Duration {
        .seconds(1)
    }

    override fileprivate var type: Int32 {
        SOCK_DGRAM
    }

    override public var connectionPrefix: String {
        "\(OcaUdpConnectionPrefix)/\(deviceAddressToString(deviceAddress))"
    }

    override public var isDatagram: Bool { true }
}

public final class Ocp1CFSocketTCPConnection: Ocp1CFSocketConnection {
    override fileprivate var type: Int32 {
        SOCK_STREAM
    }

    override public var connectionPrefix: String {
        "\(OcaTcpConnectionPrefix)/\(deviceAddressToString(deviceAddress))"
    }

    override public var isDatagram: Bool { false }
}

fileprivate func isStreamType(_ type: Int32) -> Bool {
    type == SOCK_STREAM
}

fileprivate extension Data {
    var cfData: CFData {
        #if canImport(Darwin)
        return self as NSData
        #else
        return unsafeBitCast(self as NSData, to: CFData.self)
        #endif
    }
}

fileprivate extension CFData {
    var data: Data {
        Data(referencing: unsafeBitCast(self, to: NSData.self))
    }
}

#if !canImport(Darwin)
fileprivate extension CFRunLoopMode {
    static var defaultMode: CFRunLoopMode {
        kCFRunLoopDefaultMode
    }
}
#endif

#endif
