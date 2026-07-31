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

/// What a discovery listener reports back to its owner.
public enum AndroidNsdDiscoveryEvent: Sendable {
  case started(serviceType: String)
  case stopped(serviceType: String)
  case found(AndroidNsdServiceDescriptor)
  case lost(AndroidNsdServiceDescriptor)
  case failed(AndroidNsdError)
}

/// The subset of `NsdServiceInfo` carried out of a callback.
///
/// The Java object itself is not retained: it belongs to the callback thread,
/// and `NsdServiceInfo` is mutable. Everything needed downstream is copied out
/// eagerly instead.
public struct AndroidNsdServiceDescriptor: Sendable, Equatable, Hashable {
  public let name: String
  public let serviceType: String

  init(_ serviceInfo: NsdServiceInfo) {
    name = serviceInfo.getServiceName()
    serviceType = serviceInfo.getServiceType()
  }
}

public extension AndroidNsdDiscoveryListener {
  typealias Handler = @Sendable (AndroidNsdDiscoveryEvent) -> ()

  fileprivate final class HandlerHolder {
    let _handler: Handler

    init(_ handler: @escaping Handler) {
      _handler = handler
    }

    func emit(_ event: AndroidNsdDiscoveryEvent) {
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

@JavaImplementation("com.padl.SwiftOCA.AndroidNsdDiscoveryListener")
extension AndroidNsdDiscoveryListener: AndroidNsdDiscoveryListenerNativeMethods {
  @JavaMethod
  public func onDiscoveryStarted(_ serviceType: String) {
    handlerHolder.emit(.started(serviceType: serviceType))
  }

  @JavaMethod
  public func onDiscoveryStopped(_ serviceType: String) {
    handlerHolder.emit(.stopped(serviceType: serviceType))
  }

  @JavaMethod
  public func onServiceFound(_ serviceInfo: NsdServiceInfo?) {
    guard let serviceInfo else { return }
    handlerHolder.emit(.found(AndroidNsdServiceDescriptor(serviceInfo)))
  }

  @JavaMethod
  public func onServiceLost(_ serviceInfo: NsdServiceInfo?) {
    guard let serviceInfo else { return }
    handlerHolder.emit(.lost(AndroidNsdServiceDescriptor(serviceInfo)))
  }

  @JavaMethod
  public func onStartDiscoveryFailed(_ serviceType: String, _ errorCode: Int32) {
    handlerHolder.emit(.failed(.discoveryFailed(errorCode)))
  }

  @JavaMethod
  public func onStopDiscoveryFailed(_ serviceType: String, _ errorCode: Int32) {
    handlerHolder.emit(.failed(.discoveryFailed(errorCode)))
  }
}
