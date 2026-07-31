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

/// Bridges `NsdManager.DiscoveryListener` to Swift.
///
/// Callbacks are delivered on a binder thread. Those are Java threads, so JNI
/// is already attached by the time Swift is entered.
public final class AndroidNsdDiscoveryListener extends SwiftHeapObjectHolder
    implements NsdManager.DiscoveryListener {
  public AndroidNsdDiscoveryListener(long swiftObject) {
    super(swiftObject);
  }

  public native void onDiscoveryStarted(String serviceType);

  public native void onDiscoveryStopped(String serviceType);

  public native void onServiceFound(NsdServiceInfo serviceInfo);

  public native void onServiceLost(NsdServiceInfo serviceInfo);

  public native void onStartDiscoveryFailed(String serviceType, int errorCode);

  public native void onStopDiscoveryFailed(String serviceType, int errorCode);
}
