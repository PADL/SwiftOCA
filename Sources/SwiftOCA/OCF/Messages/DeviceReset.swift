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

/// AES70-4 6.3.8: a Device Reset request carrying the 16-byte key set with
/// `OcaDeviceManager.SetResetKey`. OCP.2 only; carried as a `.ocaCmd` PDU in the
/// message model. Neither side acts on it yet.
public struct Ocp2DeviceReset: Ocp1Message, Sendable {
  public let resetKey: Data

  public var messageSize: OcaUint32 { OcaUint32(resetKey.count) }

  public init(resetKey: Data) {
    self.resetKey = resetKey
  }
}
