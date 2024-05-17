//
// Copyright (c) 2023-2024 PADL Software Pty Ltd
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
import AsyncExtensions
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
  let connection = Unmanaged<_CFSocketWrapper>.fromOpaque(info).takeUnretainedValue()
  connection.dataCallBack(cfSocket, type, address, data)
}

private func cfSocketWrapperAcceptCallback(
  _ cfSocket: CFSocket?,
  _ type: CFSocketCallBackType,
  _ address: CFData?,
  _ data: UnsafeRawPointer?,
  _ info: UnsafeMutableRawPointer?
) {
  guard let info else { return }
  let connection = Unmanaged<_CFSocketWrapper>.fromOpaque(info).takeUnretainedValue()
  connection.acceptCallBack(cfSocket, type, address, data)
}

private func mappedLastErrno() -> Error {
  if errno == EBADF || errno == ESHUTDOWN || errno == EPIPE || errno == 0 {
    return Ocp1Error.notConnected
  } else {
    return Errno(rawValue: errno)
  }
}

@_spi(SwiftOCAPrivate)
public final class _CFSocketWrapper: @unchecked
Sendable, CustomStringConvertible, Hashable {
  public static func == (lhs: _CFSocketWrapper, rhs: _CFSocketWrapper) -> Bool {
    lhs.cfSocket.nativeHandle == rhs.cfSocket.nativeHandle
  }

  private enum Element {
    case data(Data)
    case message(CFSocket.Message)
    case nativeHandle(_CFSocketWrapper)

    var data: Data {
      switch self {
      case let .data(data):
        return data
      case let .message(message):
        return message.1
      case .nativeHandle:
        return Data()
      }
    }

    var message: CFSocket.Message {
      switch self {
      case let .message(message):
        return message
      default:
        fatalError("attempted to read message from datagram socket")
      }
    }

    var nativeHandle: _CFSocketWrapper {
      switch self {
      case let .nativeHandle(socket):
        return socket
      default:
        fatalError("attemped to drain TCP accept socket")
      }
    }
  }

  private let channel = AsyncThrowingChannel<Element, Error>()
  private var receivedData: Data!
  private var cfSocket: CFSocket!
  private let isDatagram: Bool

  public var acceptedSockets: AnyAsyncSequence<_CFSocketWrapper> {
    channel.map(\.nativeHandle).eraseToAnyAsyncSequence()
  }

  public var receivedMessages: AnyAsyncSequence<CFSocket.Message> {
    channel.map(\.message).eraseToAnyAsyncSequence()
  }

  fileprivate nonisolated func dataCallBack(
    _ cfSocket: CFSocket?,
    _ type: CFSocketCallBackType,
    _ address: CFData?,
    _ cfData: UnsafeRawPointer?
  ) {
    precondition(Thread.isMainThread)

    guard let cfData else { return }
    let data = Unmanaged<CFData>.fromOpaque(cfData).takeUnretainedValue().data
    guard data.count > 0 else {
      if errno == 0 {
        channel.fail(Ocp1Error.notConnected)
      } else {
        channel.fail(Errno(rawValue: errno))
      }
      return
    }

    Task {
      if isDatagram {
        let address = try! AnySocketAddress(bytes: Array(address!.data))
        await channel.send(.message((address, data)))
      } else {
        await channel.send(.data(data))
      }
    }
  }

  fileprivate nonisolated func acceptCallBack(
    _ cfSocket: CFSocket?,
    _ type: CFSocketCallBackType,
    _ address: CFData?,
    _ nativeHandle: UnsafeRawPointer?
  ) {
    nativeHandle!.withMemoryRebound(to: CFSocketNativeHandle.self, capacity: 1) { nativeHandle in
      let nativeHandle = nativeHandle.pointee
      Task {
        let socket = try await _CFSocketWrapper(nativeHandle: nativeHandle)
        await channel.send(.nativeHandle(socket))
      }
    }
  }

  deinit {
    channel.finish()
  }

  public struct Options: OptionSet, Sendable {
    public typealias RawValue = UInt32

    public let rawValue: RawValue

    public init(rawValue: RawValue) { self.rawValue = rawValue }

    public static let server = Options(rawValue: 1 << 0)
  }

  public init(
    address: any SocketAddress,
    type: Int32,
    options: Options = []
  ) async throws {
    let proto: CInt
    if address.family == AF_INET || address.family == AF_INET6 {
      proto = type == SOCK_STREAM ? IPPROTO_TCP : IPPROTO_UDP
    } else {
      proto = 0
    }
    isDatagram = type == SOCK_DGRAM

    var context = CFSocketContext()
    context.info = Unmanaged.passUnretained(self).toOpaque()
    let cfSocket: CFSocket?

    if options.contains(.server), type == SOCK_STREAM {
      cfSocket = CFSocketCreate(
        kCFAllocatorDefault,
        Int32(address.family),
        SOCK_STREAM,
        proto,
        CFSocketCallBackType.acceptCallBack.rawValue,
        cfSocketWrapperAcceptCallback,
        &context
      )
    } else {
      cfSocket = CFSocketCreate(
        kCFAllocatorDefault,
        Int32(address.family),
        type,
        proto,
        CFSocketCallBackType.dataCallBack.rawValue,
        cfSocketWrapperDataCallback,
        &context
      )
    }

    guard let cfSocket else {
      throw Errno.socketNotConnected
    }
    self.cfSocket = cfSocket
    if proto == IPPROTO_TCP {
      try? cfSocket.setTcpNoDelay()
    }

    if options.contains(.server) {
      switch type {
      case SOCK_STREAM:
        try cfSocket.setReuseAddr()
        fallthrough
      case SOCK_DGRAM:
        try cfSocket.set(address: address)
      default:
        break
      }
    } else {
      if type == SOCK_STREAM {
        receivedData = Data()
      }
      try cfSocket.connect(to: address)
    }
    try await _addSocketToRunLoop()
  }

  init(nativeHandle: CFSocketNativeHandle) async throws {
    var context = CFSocketContext()
    isDatagram = false
    context.info = Unmanaged.passUnretained(self).toOpaque()
    let cfSocket: CFSocket?

    cfSocket = CFSocketCreateWithNative(
      kCFAllocatorDefault,
      nativeHandle,
      CFSocketCallBackType.dataCallBack.rawValue,
      cfSocketWrapperDataCallback,
      &context
    )

    guard let cfSocket else {
      throw Errno.socketNotConnected
    }
    self.cfSocket = cfSocket

    try? cfSocket.setTcpNoDelay()
    receivedData = Data()
    try await _addSocketToRunLoop()
  }

  private func _addSocketToRunLoop() async throws {
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

  private func drainChannel(atLeast length: Int) async throws {
    guard receivedData.count < length else { return }

    for try await data in channel {
      receivedData += data.data
      guard receivedData.count < length else { return }
    }
  }

  public func read(count: Int) async throws -> Data {
    precondition(!isDatagram)

    while receivedData.count < count {
      try await drainChannel(atLeast: count)
    }

    // NOTE: make a copy here, otherwise we will have concurrent access
    let data = Data(receivedData.prefix(count))
    receivedData = receivedData.dropFirst(count)

    return data
  }

  private func _write(_ bytes: [UInt8]) throws -> Int {
    let n: Int

    #if os(Linux)
    n = Glibc.write(cfSocket.nativeHandle, bytes, bytes.count)
    #else
    n = Darwin.write(cfSocket.nativeHandle, bytes, bytes.count)
    #endif
    if n < 0 { throw Errno(rawValue: errno) }
    return n
  }

  @discardableResult
  public func write(data: Data) async throws -> Int {
    var nwritten = 0

    repeat {
      nwritten += try _write(Array(data[nwritten..<data.count]))
      await Task.yield()
    } while nwritten < data.count

    return nwritten
  }

  public func send(data: Data, to address: (any SocketAddress)? = nil) throws {
    let result = CFSocketSendData(cfSocket, address?.asData().cfData, data.cfData, 0)
    switch result {
    case .success:
      break
    case .timeout:
      throw Ocp1Error.responseTimeout
    case .error:
      fallthrough
    default:
      throw Ocp1Error.pduSendingFailed
    }
  }

  public var description: String {
    String(describing: cfSocket)
  }

  public var peerAddress: AnySocketAddress? {
    try? cfSocket.peerAddress
  }

  public var peerName: String {
    (try? cfSocket.peerName) ?? "unknown"
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(cfSocket.nativeHandle)
  }
}

public class Ocp1CFSocketConnection: Ocp1Connection {
  fileprivate let deviceAddress: AnySocketAddress
  fileprivate var socket: _CFSocketWrapper?
  fileprivate var type: Int32 {
    fatalError("must be implemented by subclass")
  }

  private init(
    deviceAddress: AnySocketAddress,
    options: Ocp1ConnectionOptions = Ocp1ConnectionOptions()
  ) throws {
    self.deviceAddress = deviceAddress
    super.init(options: options)
  }

  public convenience init(
    deviceAddress: Data,
    options: Ocp1ConnectionOptions = Ocp1ConnectionOptions()
  ) throws {
    let deviceAddress = try AnySocketAddress(bytes: Array(deviceAddress))
    try self.init(deviceAddress: deviceAddress, options: options)
  }

  public convenience init(
    path: String,
    options: Ocp1ConnectionOptions = Ocp1ConnectionOptions()
  ) throws {
    let deviceAddress = try AnySocketAddress(
      family: sa_family_t(AF_LOCAL),
      presentationAddress: path
    )
    try self.init(deviceAddress: deviceAddress, options: options)
  }

  private var family: sa_family_t {
    deviceAddress.family
  }

  override func connectDevice() async throws {
    socket = try await _CFSocketWrapper(address: deviceAddress, type: type)
    try await super.connectDevice()
  }

  override public func disconnectDevice(clearObjectCache: Bool) async throws {
    socket = nil
    try await super.disconnectDevice(clearObjectCache: clearObjectCache)
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

  override public func read(_ length: Int) async throws -> Data {
    guard let socket else { throw Ocp1Error.notConnected }
    var iterator = socket.receivedMessages.makeAsyncIterator()
    guard let data = try await iterator.next()?.1 else {
      throw Ocp1Error.notConnected
    }
    return data
  }

  override public func write(_ data: Data) async throws -> Int {
    guard let socket else { throw Ocp1Error.notConnected }
    try socket.send(data: data)
    return data.count
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

  override public func read(_ length: Int) async throws -> Data {
    guard let socket else { throw Ocp1Error.notConnected }
    return try await socket.read(count: length)
  }

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
    withSockAddr { sa in
      withUnsafeBytes(of: sa.pointee) {
        Data(bytes: $0.baseAddress!, count: $0.count)
      }
    }
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

  static func throwingErrno(_ block: () -> CFSocketError) throws {
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

  var nativeHandle: CFSocketNativeHandle {
    CFSocketGetNative(self)
  }

  func set(address: any SocketAddress) throws {
    try CFSocket.throwingErrno {
      CFSocketSetAddress(self, address.asData().cfData)
    }
  }

  func connect(to address: any SocketAddress) throws {
    try CFSocket.throwingErrno {
      CFSocketConnectToAddress(self, address.asData().cfData, 0)
    }
  }

  typealias Message = (any SocketAddress, Data)

  func sendMessage(_ message: Message) throws {
    try CFSocket.throwingErrno {
      CFSocketSendData(self, message.0.asData().cfData, message.1.cfData, 0)
    }
  }

  #if false
  func bind(to address: any SocketAddress) throws {
    _ = try address.withSockAddr { sockaddr in
      try Errno.throwingGlobalErrno {
        #if canImport(Darwin)
        Darwin.bind(self.nativeHandle, sockaddr, sockaddr.pointee.size)
        #elseif canImport(Glibc)
        Glibc.bind(self.nativeHandle, sockaddr, sockaddr.pointee.size)
        #endif
      }
    }
  }
  #endif

  func setTcpNoDelay() throws {
    var option = CInt(1)
    try Errno.throwingGlobalErrno {
      setsockopt(
        self.nativeHandle,
        CInt(IPPROTO_TCP),
        TCP_NODELAY,
        &option,
        socklen_t(MemoryLayout<CInt>.size)
      )
    }
  }

  func setReuseAddr() throws {
    var option = CInt(1)
    try Errno.throwingGlobalErrno {
      setsockopt(
        self.nativeHandle,
        SOL_SOCKET,
        SO_REUSEADDR,
        &option,
        socklen_t(MemoryLayout<CInt>.size)
      )
    }
  }

  func invalidate() {
    CFSocketInvalidate(self)
  }

  func set(flags: Int32, mask: Int32) throws {
    var flags = try Errno.throwingGlobalErrno { fcntl(self.nativeHandle, F_GETFL, 0) }
    flags &= ~mask
    flags |= mask
    try Errno.throwingGlobalErrno { fcntl(self.nativeHandle, F_SETFL, flags) }
  }

  func get(flag: Int32) throws -> Bool {
    let flags = try Errno.throwingGlobalErrno { fcntl(self.nativeHandle, F_GETFL, 0) }
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
