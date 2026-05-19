//
// Copyright (c) 2026 PADL Software Pty Ltd
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

#if SwiftNIOBackend

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import NIOCore
@_spi(SwiftOCAPrivate)
import SwiftOCA

/// Bridges an `NIOSSL`-decrypted inbound `ByteBuffer` stream to the async
/// `read(_:)` contract `Ocp1Connection` and `Ocp1ControllerInternal` expect.
///
/// Reader side is single-consumer: the `Ocp1Connection` monitor task and the
/// server-side receive task each own their bridge and call `read` serially.
/// Outbound writes go through `Channel.writeAndFlush` directly; this handler
/// is inbound-only.
package final class Ocp1NIOByteBufferBridge: ChannelInboundHandler, @unchecked Sendable {
  package typealias InboundIn = ByteBuffer

  private let _continuation: AsyncThrowingStream<ByteBuffer, any Error>.Continuation
  /// Owned exclusively by `read(_:)` — must not be touched from the event loop.
  private var _iterator: AsyncThrowingStream<ByteBuffer, any Error>.AsyncIterator
  private var _accumulator: ByteBuffer

  package init() {
    let (stream, continuation) = AsyncThrowingStream<ByteBuffer, any Error>.makeStream()
    _continuation = continuation
    _iterator = stream.makeAsyncIterator()
    _accumulator = ByteBuffer()
  }

  // MARK: - ChannelInboundHandler (event loop)

  public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
    _continuation.yield(unwrapInboundIn(data))
  }

  public func channelInactive(context: ChannelHandlerContext) {
    _continuation.finish()
    context.fireChannelInactive()
  }

  public func errorCaught(context: ChannelHandlerContext, error: any Error) {
    _continuation.finish(throwing: error)
    context.fireErrorCaught(error)
  }

  // MARK: - Reader (Swift Concurrency)

  /// Returns exactly `length` plaintext bytes from the TLS channel, or
  /// throws `Ocp1Error.notConnected` on EOF / handshake failure.
  package func read(_ length: Int) async throws -> Data {
    while _accumulator.readableBytes < length {
      do {
        guard var next = try await _iterator.next() else {
          throw Ocp1Error.notConnected
        }
        _accumulator.writeBuffer(&next)
      } catch is Ocp1Error {
        throw Ocp1Error.notConnected
      } catch {
        throw Ocp1Error.notConnected
      }
    }
    guard let bytes = _accumulator.readBytes(length: length) else {
      throw Ocp1Error.notConnected
    }
    return Data(bytes)
  }

  /// Idempotent close: terminates the inbound stream so a pending `read`
  /// throws `Ocp1Error.notConnected` rather than hanging.
  package func close() {
    _continuation.finish()
  }
}

#endif
