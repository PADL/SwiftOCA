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


@_spi(SwiftOCAPrivate)
import SwiftOCA
import Logging

/// Advertises a service of the caller's DNS-SD type (not an OCA endpoint's) under the device's
/// name, registering it again whenever the device is renamed, until the task is cancelled.
///
/// A registration that fails, because no DNS-SD responder is running yet say, is logged and
/// retried, waiting `retryDelay`'s lower bound at first and twice as long each time after, up
/// to its upper bound. It never ends the caller's service: this returns only when cancelled
/// or when the name stops changing for good. Without DNS-SD it waits to be cancelled.
@_spi(SwiftOCAPrivate)
@OcaDevice
public func runDNSServiceRegistrar(
  regType: String,
  port: UInt16,
  txtRecord: [(String, String)],
  deviceManager: OcaDeviceManager,
  logger: Logger,
  retryDelay: ClosedRange<Duration> = .seconds(1)...Duration.seconds(60)
) async {
  #if canImport(dnssd)
  var registration: DNSServiceRegistration?
  do {
    for try await deviceName in deviceManager.$deviceName {
      await registration?.deregister()
      registration = nil
      var delay = retryDelay.lowerBound
      while registration == nil {
        try Task.checkCancellation()
        do {
          registration = try await DNSServiceRegistration(name: deviceName, regType: regType, port: port, txtRecord: txtRecord)
        } catch {
          logger.warning("could not advertise \(regType) on port \(port), retrying: \(error)")
          try await Task.sleep(for: delay)
          delay = min(delay * 2, retryDelay.upperBound)
        }
      }
    }
  } catch {
    // cancelled
  }
  // deregistered at once, so that the responder sends its goodbye while the process runs
  await registration?.deregister()
  #else
  let (cancellation, continuation) = AsyncStream<Never>.makeStream()
  await withTaskCancellationHandler {
    for await _ in cancellation {}
  } onCancel: {
    continuation.finish()
  }
  #endif
}
