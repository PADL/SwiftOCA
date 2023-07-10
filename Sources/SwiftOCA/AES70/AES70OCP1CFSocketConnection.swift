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

private func AES70OCP1CFSocketConnection_DataCallBack(
    _ socket: CFSocket?,
    _ type: CFSocketCallBackType,
    _ address: CFData?,
    _ data: UnsafeRawPointer?,
    _ info: UnsafeMutableRawPointer?
) {
    guard let info else { return }
    let connection = Unmanaged<AES70OCP1CFSocketConnection>.fromOpaque(info).takeUnretainedValue()
    connection.dataCallBack(socket, type, address, data)
}

public class AES70OCP1CFSocketConnection: AES70OCP1Connection {
    private let deviceAddress: Data
    fileprivate var cfSocket: CFSocket?
    fileprivate var type: Int32 {
        fatalError("must be implemented by subclass")
    }

    private var receivedDataChannel = AsyncChannel<Data>()
    private var receivedData = Data()

    @MainActor
    public init(
        deviceAddress: Data,
        options: AES70OCP1ConnectionOptions = AES70OCP1ConnectionOptions()
    ) {
        self.deviceAddress = deviceAddress
        super.init(options: options)
    }

    deinit {
        if let cfSocket {
            CFSocketInvalidate(cfSocket)
        }
    }

    fileprivate func dataCallBack(
        _ socket: CFSocket?,
        _ type: CFSocketCallBackType,
        _ address: CFData?,
        _ cfData: UnsafeRawPointer?
    ) {
        guard let cfData else { return }
        let data = Unmanaged<CFData>.fromOpaque(cfData).takeUnretainedValue() as Data
        guard data.count > 0 else { return }

        Task {
            await receivedDataChannel.send(data)
        }
    }

    @MainActor
    override func connectDevice() async throws {
        var context = CFSocketContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        let cfSocket = CFSocketCreate(
            kCFAllocatorDefault,
            AF_INET,
            type,
            type == SOCK_STREAM ? IPPROTO_TCP : IPPROTO_UDP,
            CFSocketCallBackType.dataCallBack.rawValue,
            AES70OCP1CFSocketConnection_DataCallBack,
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

        DispatchQueue.main.async {
            let runLoopSource = CFSocketCreateRunLoopSource(kCFAllocatorDefault, cfSocket, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, CFRunLoopMode.defaultMode)
        }

        guard CFSocketIsValid(cfSocket),
              CFSocketConnectToAddress(cfSocket, deviceAddress as CFData, 0) == .success
        else {
            throw Ocp1Error.notConnected
        }

        self.cfSocket = cfSocket

        try await super.connectDevice()
    }

    @MainActor
    override func disconnectDevice(clearObjectCache: Bool) async throws {
        if let cfSocket {
            CFSocketInvalidate(cfSocket)
            self.cfSocket = nil
        }

        try await super.disconnectDevice(clearObjectCache: clearObjectCache)
    }

    @MainActor
    private func drainChannel(atLeast length: Int) async {
        guard receivedData.count < length else { return }

        for await data in receivedDataChannel {
            receivedData += data
            guard receivedData.count < length else { return }
        }
    }

    @MainActor
    override func read(_ length: Int) async throws -> Data {
        while receivedData.count < length {
            await drainChannel(atLeast: length)
        }

        // NOTE: make a copy here, otherwise we will have concurrent access
        let data = Data(receivedData.prefix(length))
        receivedData = receivedData.dropFirst(length)

        return data
    }

    @MainActor
    override func write(_ data: Data) async throws -> Int {
        guard let cfSocket else {
            throw Ocp1Error.notConnected
        }
        let result = CFSocketSendData(cfSocket, nil, data as CFData, 0)
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

public class AES70OCP1CFSocketUDPConnection: AES70OCP1CFSocketConnection {
    override public var keepAliveInterval: OcaUint16 {
        1
    }

    override fileprivate var type: Int32 {
        SOCK_DGRAM
    }
}

public class AES70OCP1CFSocketTCPConnection: AES70OCP1CFSocketConnection {
    override fileprivate var type: Int32 {
        SOCK_STREAM
    }
}
