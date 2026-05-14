//
// Copyright (c) 2026 PADL Software Pty Ltd
//
// Licensed under the Apache License, Version 2.0 (the License);
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//

#if os(Linux)
#if canImport(COpenSSL) && canImport(IORing)

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
@_spi(SwiftOCAPrivate)
import SwiftOCA
import SwiftOCASecure
@testable import SwiftOCASecureDevice
import Synchronization

/// In-memory bidirectional `Ocp1ByteStream` pair used by tests to exercise
/// `Ocp1OpenSSLEngine` end-to-end without opening a real socket. Each call
/// to `write(_:)` on one end becomes available on the partner's `read(...)`
/// in chunk order. Reads suspend until data arrives or the partner closes
/// (EOF surfaces as `Ocp1Error.notConnected`, matching real-socket
/// semantics).
///
/// Each direction is backed by a shared `PipeChannel` (see below) — one
/// per partner pair, two per stream. That way `read` and `write` on the
/// same end never block each other (they touch *different* channels) and
/// concurrent reads from competing tasks are serialised by the channel's
/// internal lock.
actor PipeByteStream: Ocp1ByteStream {
  private let inbound: PipeChannel
  private let outbound: PipeChannel

  private init(inbound: PipeChannel, outbound: PipeChannel) {
    self.inbound = inbound
    self.outbound = outbound
  }

  /// Make a connected pair `(a, b)` such that bytes written to `a` appear
  /// on reads from `b`, and vice versa.
  static func makePair() -> (PipeByteStream, PipeByteStream) {
    let aToB = PipeChannel()
    let bToA = PipeChannel()
    let a = PipeByteStream(inbound: bToA, outbound: aToB)
    let b = PipeByteStream(inbound: aToB, outbound: bToA)
    return (a, b)
  }

  func write(_ data: Data) async throws {
    try outbound.send(data)
  }

  func read(count: Int, awaitingAllRead: Bool) async throws -> Data {
    if !awaitingAllRead {
      return try await inbound.receive(maxBytes: count)
    }
    var result = Data()
    result.reserveCapacity(count)
    while result.count < count {
      let chunk = try await inbound.receive(maxBytes: count - result.count)
      result.append(chunk)
    }
    return result
  }

  func close() async {
    outbound.finish()
  }
}

// MARK: - PipeChannel

/// Continuation-based byte channel used by `PipeByteStream`. Producers
/// `send` chunks; consumers `receive` up to `maxBytes` from the head.
/// One pending consumer at a time (single-task-per-direction matches
/// `OcaByteStream`'s contract); concurrent receivers serialise.
final class PipeChannel: Sendable {
  private struct State {
    var buffer = Data()
    var finished = false
    var pending: CheckedContinuation<Void, Never>?
  }

  private let state = Mutex(State())

  func send(_ data: Data) throws {
    let toResume: CheckedContinuation<Void, Never>? = try state.withLock {
      (state: inout State) -> CheckedContinuation<Void, Never>? in
      if state.finished { throw Ocp1Error.notConnected }
      state.buffer.append(data)
      let p = state.pending
      state.pending = nil
      return p
    }
    toResume?.resume()
  }

  func finish() {
    let toResume = state.withLock { (state: inout State) -> CheckedContinuation<Void, Never>? in
      state.finished = true
      let p = state.pending
      state.pending = nil
      return p
    }
    toResume?.resume()
  }

  func receive(maxBytes: Int) async throws -> Data {
    while true {
      enum Outcome { case data(Data); case eof; case wait }
      let outcome: Outcome = state.withLock { (state: inout State) -> Outcome in
        if !state.buffer.isEmpty {
          let n = Swift.min(maxBytes, state.buffer.count)
          let slice = Data(state.buffer.prefix(n))
          state.buffer = state.buffer.dropFirst(n)
          return .data(slice)
        }
        if state.finished { return .eof }
        return .wait
      }
      switch outcome {
      case let .data(slice): return slice
      case .eof: throw Ocp1Error.notConnected
      case .wait:
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
          state.withLock { (state: inout State) in
            // If a producer raced with us between the first lock and here,
            // re-check before parking — otherwise the resume is lost.
            if !state.buffer.isEmpty || state.finished {
              cont.resume()
            } else {
              state.pending = cont
            }
          }
        }
      }
    }
  }
}

#endif
#endif
