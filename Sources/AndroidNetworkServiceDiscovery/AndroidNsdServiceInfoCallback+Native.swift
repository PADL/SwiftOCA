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

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftJava

/// A resolved snapshot of a service.
///
/// Copied eagerly out of the callback's `NsdServiceInfo`, which is mutable and
/// belongs to the calling thread.
public struct AndroidNsdResolution: Sendable, Equatable, Hashable {
  public let hostname: String
  public let port: UInt16
  /// Presentation-form addresses, e.g. "192.0.2.4", zone index stripped.
  public let addresses: [String]
  public let txtRecords: [String: String]

  init(_ serviceInfo: NsdServiceInfo, helper: JavaClass<AndroidNsdServiceInfoHelper>) {
    hostname = serviceInfo.getHostname()
    port = UInt16(truncatingIfNeeded: serviceInfo.getPort())
    addresses = helper.hostAddresses(serviceInfo)

    // Flattened [key0, value0, key1, value1, ...]; see the Java helper.
    let flattened = helper.attributes(serviceInfo)
    var txtRecords = [String: String]()
    for pair in stride(from: 0, to: flattened.count - 1, by: 2) {
      txtRecords[flattened[pair]] = flattened[pair + 1]
    }
    self.txtRecords = txtRecords
  }
}

public enum AndroidNsdServiceInfoEvent: Sendable {
  case updated(AndroidNsdResolution)
  case lost
  case unregistered
  case failed(AndroidNsdError)
}

public extension AndroidNsdServiceInfoCallback {
  typealias Handler = @Sendable (AndroidNsdServiceInfoEvent) -> ()

  fileprivate final class HandlerHolder {
    let _handler: Handler

    init(_ handler: @escaping Handler) {
      _handler = handler
    }

    func emit(_ event: AndroidNsdServiceInfoEvent) {
      _handler(event)
    }
  }

  private var handlerHolder: HandlerHolder {
    swiftObject as! HandlerHolder
  }

  convenience init(_ handler: @escaping Handler) {
    self.init(handlerHolder: HandlerHolder(handler))
  }

  private convenience init(
    handlerHolder: HandlerHolder,
    environment: JNIEnvironment? = nil
  ) {
    self.init(swiftObject: handlerHolder, environment: environment)
  }
}

@JavaImplementation("com.padl.SwiftOCA.AndroidNsdServiceInfoCallback")
extension AndroidNsdServiceInfoCallback: AndroidNsdServiceInfoCallbackNativeMethods {
  @JavaMethod
  public func onServiceInfoCallbackRegistrationFailed(_ errorCode: Int32) {
    handlerHolder.emit(.failed(.resolutionFailed(errorCode)))
  }

  @JavaMethod
  public func onServiceUpdated(_ serviceInfo: NsdServiceInfo?) {
    guard let serviceInfo, let helper = try? JavaClass<AndroidNsdServiceInfoHelper>() else {
      return
    }
    handlerHolder.emit(.updated(AndroidNsdResolution(serviceInfo, helper: helper)))
  }

  @JavaMethod
  public func onServiceLost() {
    handlerHolder.emit(.lost)
  }

  @JavaMethod
  public func onServiceInfoCallbackUnregistered() {
    handlerHolder.emit(.unregistered)
  }
}
