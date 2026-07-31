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

package com.padl.SwiftOCA;

import android.net.nsd.NsdManager;
import android.net.nsd.NsdServiceInfo;

/// Bridges `NsdManager.ServiceInfoCallback` (API 34+) to Swift.
///
/// This is the modern replacement for `NsdManager.ResolveListener`. It is used
/// in preference to `resolveService()` because the legacy call permits only one
/// in-flight resolve per `NsdManager` and fails concurrent callers with
/// FAILURE_ALREADY_ACTIVE -- which the connection broker would trip as soon as
/// a second OCA device appeared. It also keeps delivering updates as the
/// service's addresses change, rather than resolving once.
public final class AndroidNsdServiceInfoCallback extends SwiftHeapObjectHolder
    implements NsdManager.ServiceInfoCallback {
  public AndroidNsdServiceInfoCallback(long swiftObject) {
    super(swiftObject);
  }

  public native void onServiceInfoCallbackRegistrationFailed(int errorCode);

  public native void onServiceUpdated(NsdServiceInfo serviceInfo);

  public native void onServiceLost();

  public native void onServiceInfoCallbackUnregistered();
}
