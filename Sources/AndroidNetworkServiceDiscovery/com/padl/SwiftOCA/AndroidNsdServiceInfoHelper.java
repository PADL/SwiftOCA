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

import android.net.nsd.NsdServiceInfo;
import java.net.InetAddress;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/// Flattens the awkward corners of `NsdServiceInfo` into String arrays.
///
/// `getAttributes()` is a `Map<String, byte[]>` and `getHostAddresses()` a
/// `List<InetAddress>`; both are painful to traverse across the swift-java
/// boundary. Doing it in Java costs a few lines and keeps the Swift side free
/// of JavaMap/JavaArray handling.
public final class AndroidNsdServiceInfoHelper {
  private AndroidNsdServiceInfoHelper() {}

  /// TXT records flattened to [key0, value0, key1, value1, ...].
  ///
  /// Attributes with a null value are conventional in DNS-SD (the key's mere
  /// presence is the signal) and are reported with an empty string value.
  public static String[] attributes(NsdServiceInfo serviceInfo) {
    Map<String, byte[]> attributes = serviceInfo.getAttributes();
    if (attributes == null) {
      return new String[0];
    }
    List<String> flattened = new ArrayList<>(attributes.size() * 2);
    for (Map.Entry<String, byte[]> entry : attributes.entrySet()) {
      byte[] value = entry.getValue();
      flattened.add(entry.getKey());
      flattened.add(value == null ? "" : new String(value, StandardCharsets.UTF_8));
    }
    return flattened.toArray(new String[0]);
  }

  /// Host addresses in presentation form, e.g. "192.0.2.4" or "2001:db8::1".
  public static String[] hostAddresses(NsdServiceInfo serviceInfo) {
    List<InetAddress> addresses = serviceInfo.getHostAddresses();
    if (addresses == null) {
      return new String[0];
    }
    List<String> presentation = new ArrayList<>(addresses.size());
    for (InetAddress address : addresses) {
      String hostAddress = address.getHostAddress();
      if (hostAddress != null) {
        // Strip any zone index; SocketAddress does not accept "fe80::1%wlan0".
        int zone = hostAddress.indexOf('%');
        presentation.add(zone < 0 ? hostAddress : hostAddress.substring(0, zone));
      }
    }
    return presentation.toArray(new String[0]);
  }
}
