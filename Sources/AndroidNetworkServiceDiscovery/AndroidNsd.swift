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

/// Process-wide Android NSD configuration.
///
/// `NsdManager` is only reachable through `Context.getSystemService()`, and
/// `OcaNetworkAdvertisingServiceBrowser.init(serviceType:)` has nowhere to carry
/// a `Context`. Rather than widen that protocol for one platform's benefit, the
/// host application hands a `Context` over once at startup.
///
/// Call this before constructing an `OcaConnectionBroker`; browsing throws
/// `Ocp1Error.notImplemented` until it has been called.
///
/// Pass the *application* context, not an Activity: Android may destroy and
/// recreate the Activity while the broker outlives it, and holding the Activity
/// here would leak it.
public enum AndroidNsd {
  nonisolated(unsafe) static var _classLoader: JavaClassLoader!
  nonisolated(unsafe) static var _nsdManager: NsdManager!
  nonisolated(unsafe) static var _mainExecutor: JavaExecutor!

  /// Whether `configure(context:)` has been called successfully.
  public static var isConfigured: Bool {
    _nsdManager != nil
  }

  /// Supplies the Android `Context` used to reach `NsdManager`.
  ///
  /// Must be called from a thread originating in Java -- typically the JNI entry
  /// point that starts the host application -- because the class loader capture
  /// below cannot succeed on a thread JNI did not create.
  public static func configure(context: AndroidContext) throws {
    // Capturing the class loader is what makes the listener shims findable from
    // the binder threads NSD delivers callbacks on. See
    // SwiftHeapObjectHolder+Native.swift.
    let holderClass = try JavaClass<SwiftHeapObjectHolder>()
    _classLoader = holderClass.getClassLoader()
    guard _classLoader != nil else {
      throw AndroidNsdError.classLoaderUnavailable
    }

    // NSD_SERVICE is a static field, so it hangs off the class, not an instance.
    let contextClass = try JavaClass<AndroidContext>()
    guard let nsdManager = context
      .getSystemService(contextClass.NSD_SERVICE)?.as(NsdManager.self)
    else {
      throw AndroidNsdError.nsdManagerUnavailable
    }
    _nsdManager = nsdManager

    // registerServiceInfoCallback needs an Executor to deliver on; the main
    // executor is the least surprising choice and avoids us owning a thread
    // pool. Callbacks are bridged onto an AsyncStream immediately, so nothing
    // expensive runs on it.
    _mainExecutor = context.getMainExecutor()
  }

  /// `NsdManager.PROTOCOL_DNS_SD`, the only protocol Android implements.
  public static var protocolDnsSd: Int32 {
    (try? JavaClass<NsdManager>().PROTOCOL_DNS_SD) ?? 1
  }

  public static var mainExecutor: JavaExecutor {
    get throws {
      guard let _mainExecutor else {
        throw AndroidNsdError.notConfigured
      }
      return _mainExecutor
    }
  }

  public static var nsdManager: NsdManager {
    get throws {
      guard let _nsdManager else {
        throw AndroidNsdError.notConfigured
      }
      return _nsdManager
    }
  }
}

public enum AndroidNsdError: Error, Sendable {
  /// `AndroidNsd.configure(context:)` was never called.
  case notConfigured
  /// The class loader could not be captured; see `configure(context:)`.
  case classLoaderUnavailable
  /// The platform did not vend an `NsdManager`.
  case nsdManagerUnavailable
  /// NSD reported a failure; the payload is the Android error code.
  case discoveryFailed(Int32)
  case resolutionFailed(Int32)
}
