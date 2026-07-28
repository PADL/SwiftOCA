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

import SwiftOCA
import SwiftOCADevice
import Testing

@Suite
struct ClassRegistryTests {
  /// `_match()` searches downwards from `OcaRoot.classVersion`, so a device class
  /// registered at a later version than `OcaRoot` is unreachable; keep the two
  /// frameworks' idea of the root class version in step
  @Test
  func deviceAndControllerRootClassVersionsAgree() {
    #expect(SwiftOCADevice.OcaRoot.classVersion == SwiftOCA.OcaRoot.classVersion)
  }

  @Test @OcaDevice
  func resolvesClassVersion3Classes() throws {
    let registry = OcaDeviceClassRegistry.shared

    #expect(try registry.match(classID: OcaClassID("1.1.1.8"))
      == SwiftOCADevice.OcaFrequencyActuator.self)
    #expect(try registry.match(classID: OcaClassID("1.2.15"))
      == SwiftOCADevice.OcaMediaClock3.self)
    #expect(try registry.match(classID: OcaClassID("1.2.16"))
      == SwiftOCADevice.OcaTimeSource.self)
  }

  /// an unknown subclass still resolves to the nearest registered superclass
  @Test @OcaDevice
  func fallsBackToSuperclass() throws {
    let registry = OcaDeviceClassRegistry.shared

    #expect(try registry.match(classID: OcaClassID("1.1.1.9999"))
      == SwiftOCADevice.OcaActuator.self)
  }

  @Test @OcaConnection
  func controllerRegistryConstructs() {
    _ = OcaClassRegistry.shared
  }
}
