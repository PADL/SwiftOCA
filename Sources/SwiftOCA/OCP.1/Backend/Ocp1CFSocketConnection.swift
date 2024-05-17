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
// @_implementationOnly
@preconcurrency
import CoreFoundation
import Foundation
import SocketAddress
import SystemPackage
#if os(Linux)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

private func cfSocketWrapperDataCallback(
  _ cfSocket: CFSocket?,
  _ type: CFSocketCallBackType,
  _ address: CFData?,
  _ data: UnsafeRawPointer?,
  _ info: UnsafeMutableRawPointer?
) {
  guard let info else { return }
  let connection = Unmanaged<CFSocketWrapper>.fromOpaque(info).takeUnretainedValue()
  connection.dataCallBack(cfSocket, type, address, data)
}

private func mappedLastErrno() -> Error {
  if errno == EBADF || errno == ESHUTDOWN || errno == EPIPE || errno == 0 {
    return Ocp1Error.notConnected
  } else {
    return Errno(rawValue: errno)
  }
}

@_spi(SwiftOCAPrivate)
public final class CFSocketWrapper: @unchecked
Sendable {
  private let receivedDataChannel = AsyncChannel<Data>()
  private var receivedData = Data()
  fileprivate var cfSocket: CFSocket!

  fileprivate nonisolated func dataCallBack(
    _ cfSocket: CFSocket?,
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

  deinit {
    receivedDataChannel.finish()
  }

  private init() {}

  convenience init(address: any SocketAddress, protocol proto: CInt) async throws {
    var context = CFSocketContext()
    self.init()
    context.info = Unmanaged.passUnretained(self).toOpaque()

    guard let cfSocket = CFSocketCreate(
      kCFAllocatorDefault,
      Int32(address.family),
      proto == IPPROTO_UDP ? SOCK_DGRAM : SOCK_STREAM,
      proto,
      CFSocketCallBackType.dataCallBack.rawValue,
      cfSocketWrapperDataCallback,
      &context
    ) else {
      throw Errno.socketNotConnected
    }

    if address.family != AF_LOCAL, proto == IPPROTO_TCP {
      try? cfSocket.setTcpNoDelay()
    }

    try await self.init(cfSocket: cfSocket)

    guard CFSocketConnectToAddress(cfSocket, address.asData().cfData, 0) == .success else {
      throw mappedLastErrno()
    }
  }

  required init(cfSocket: CFSocket) async throws {
    self.cfSocket = cfSocket
    var options = CFSocketGetSocketFlags(cfSocket)
    options |= kCFSocketCloseOnInvalidate
    CFSocketSetSocketFlags(cfSocket, options)
    try cfSocket.setBlocking(false)

    let runLoopSource = CFSocketCreateRunLoopSource(kCFAllocatorDefault, cfSocket, 0)
    try await withTaskCancellationHandler(operation: {
      CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, CFRunLoopMode.defaultMode)
      guard CFSocketIsValid(cfSocket) else {
        throw mappedLastErrno()
      }
    }, onCancel: {
      CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, CFRunLoopMode.defaultMode)
    })
  }

  private func drainChannel(atLeast length: Int) async {
    guard receivedData.count < length else { return }

    for await data in receivedDataChannel {
      receivedData += data
      guard receivedData.count < length else { return }
    }
  }

  func read(count: Int) async throws -> Data {
    while receivedData.count < count {
      await drainChannel(atLeast: count)
    }

    // NOTE: make a copy here, otherwise we will have concurrent access
    let data = Data(receivedData.prefix(count))
    receivedData = receivedData.dropFirst(count)

    return data
  }

  private func _write(_ bytes: [UInt8]) throws -> Int {
    let n: Int

    #if os(Linux)
    n = Glibc.write(cfSocket.nativeSocketHandle, bytes, bytes.count)
    #else
    n = Darwin.write(cfSocket.nativeSocketHandle, bytes, bytes.count)
    #endif
    if n < 0 { throw Errno(rawValue: errno) }
    return n
  }

  @discardableResult
  func write(data: Data) async throws -> Int {
    var nwritten = 0

    repeat {
      nwritten += try _write(Array(data[nwritten..<data.count]))
      await Task.yield()
    } while nwritten < data.count

    return nwritten
  }

  func send(data: Data) throws -> Int {
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

public class Ocp1CFSocketConnection: Ocp1Connection {
  fileprivate let deviceAddress: AnySocketAddress
  fileprivate var socket: CFSocketWrapper?
  fileprivate var type: Int32 {
    fatalError("must be implemented by subclass")
  }

  public init(
    deviceAddress: Data,
    options: Ocp1ConnectionOptions = Ocp1ConnectionOptions()
  ) throws {
    self.deviceAddress = try AnySocketAddress(bytes: Array(deviceAddress))
    super.init(options: options)
  }

  public convenience init(
    path: String,
    options: Ocp1ConnectionOptions = Ocp1ConnectionOptions()
  ) throws {
    var sun = try sockaddr_un(family: sa_family_t(AF_UNIX), presentationAddress: path)
    let deviceAddress = Data(bytes: &sun, count: MemoryLayout<sockaddr_un>.stride)
    try self.init(deviceAddress: deviceAddress, options: options)
  }

  private var family: sa_family_t {
    deviceAddress.family
  }

  private var proto: Int32 {
    switch Int32(family) {
    case AF_INET:
      fallthrough
    case AF_INET6:
      return isStreamType(type) ? Int32(IPPROTO_TCP) : Int32(IPPROTO_UDP)
    default:
      return 0
    }
  }

  override func connectDevice() async throws {
    socket = try await CFSocketWrapper(address: deviceAddress, protocol: proto)
    try await super.connectDevice()
  }

  override public func disconnectDevice(clearObjectCache: Bool) async throws {
    socket = nil
    try await super.disconnectDevice(clearObjectCache: clearObjectCache)
  }

  override public func read(_ length: Int) async throws -> Data {
    guard let socket else { throw Ocp1Error.notConnected }
    return try await socket.read(count: length)
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
    "\(OcaUdpConnectionPrefix)/\(try! deviceAddress.presentationAddress)"
  }

  override public var isDatagram: Bool { true }

  override public func write(_ data: Data) async throws -> Int {
    guard let socket else { throw Ocp1Error.notConnected }
    return try socket.send(data: data)
  }
}

public final class Ocp1CFSocketTCPConnection: Ocp1CFSocketConnection {
  override fileprivate var type: Int32 {
    SOCK_STREAM
  }

  override public var connectionPrefix: String {
    "\(OcaTcpConnectionPrefix)/\(try! deviceAddress.presentationAddress)"
  }

  override public var isDatagram: Bool { false }

  override public func write(_ data: Data) async throws -> Int {
    guard let socket else { throw Ocp1Error.notConnected }
    return try await socket.write(data: data)
  }
}

fileprivate func isStreamType(_ type: Int32) -> Bool {
  type == SOCK_STREAM
}

@_spi(SwiftOCAPrivate)
public extension Data {
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

@_spi(SwiftOCAPrivate)
public extension SocketAddress {
  func asData() -> Data {
    withUnsafeBytes(of: asStorage) { Data(bytes: $0.baseAddress!, count: $0.count) }
  }
}

extension CFSocket: @unchecked
Sendable {}

@_spi(SwiftOCAPrivate)
public extension CFSocket {
  var address: AnySocketAddress {
    get throws {
      guard let address = CFSocketCopyAddress(self) as? Data else {
        throw Errno.addressNotAvailable
      }
      return try AnySocketAddress(bytes: Array(address))
    }
  }

  var peerAddress: AnySocketAddress {
    get throws {
      guard let address = CFSocketCopyPeerAddress(self) as? Data else {
        throw Errno.addressNotAvailable
      }
      return try AnySocketAddress(bytes: Array(address))
    }
  }

  var peerName: String {
    get throws {
      try peerAddress.presentationAddress
    }
  }

  func throwingErrno(_ block: () -> CFSocketError) throws {
    let socketError = block()
    switch socketError {
    case .error:
      throw mappedLastErrno()
    case .success:
      return
    case .timeout:
      throw Errno.timedOut
    default:
      throw Errno.invalidArgument
    }
  }

  var nativeSocketHandle: CFSocketNativeHandle {
    CFSocketGetNative(self)
  }

  typealias Message = (any SocketAddress, Data)

  func sendMessage(_ message: Message) throws {
    try throwingErrno {
      CFSocketSendData(self, message.0.asData().cfData, message.1.cfData, 0)
    }
  }

  func setTcpNoDelay() throws {
    var option = CInt(1)
    if setsockopt(
      nativeSocketHandle,
      IPPROTO_TCP,
      TCP_NODELAY,
      &option,
      socklen_t(MemoryLayout<CInt>.size)
    ) < 0 {
      throw mappedLastErrno()
    }
  }

  func invalidate() {
    CFSocketInvalidate(self)
  }

  func set(flags: Int32, mask: Int32) throws {
    var flags = try Errno.throwingGlobalErrno { fcntl(self.nativeSocketHandle, F_GETFL, 0) }
    flags &= ~mask
    flags |= mask
    try Errno.throwingGlobalErrno { fcntl(self.nativeSocketHandle, F_SETFL, flags) }
  }

  func get(flag: Int32) throws -> Bool {
    let flags = try Errno.throwingGlobalErrno { fcntl(self.nativeSocketHandle, F_GETFL, 0) }
    return flags & flag != 0
  }

  func set(flag: Int32, to enabled: Bool) throws {
    try set(flags: enabled ? flag : 0, mask: flag)
  }

  func setBlocking(_ enabled: Bool) throws {
    try set(flag: O_NONBLOCK, to: enabled)
  }

  var isBlocking: Bool {
    get throws {
      try get(flag: O_NONBLOCK)
    }
  }
}

fileprivate extension Errno {
  @discardableResult
  static func throwingGlobalErrno(_ body: @escaping () -> CInt) throws -> CInt {
    let result = body()
    if result < 0 {
      throw Errno(rawValue: errno)
    }
    return result
  }
}

#endif
