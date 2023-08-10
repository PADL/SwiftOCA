//
// Copyright (c) 2023 PADL Software Pty Ltd
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

public enum OcaNetworkLinkType: OcaUint8, Codable {
    case none = 0
    case ethernetWired = 1
    case ethernetWireless = 2
    case usb = 3
    case serialP2P = 4
}

public enum OcaNetworkMediaProtocol: OcaUint8, Codable {
    case none = 0
    case av3 = 1
    case avbtp = 2
    case dante = 3
    case cobranet = 4
    case aes67 = 5
    case smpteAudio = 6
    case liveWire = 7
    case extensionPoint = 65
}

public enum OcaNetworkControlProtocol: OcaUint8, Codable {
    case none = 0
    case ocp01 = 1 // TCP/IP
    case ocp02 = 2 // USB
    case ocp03 = 3 // JSON
}

public struct OcaNetworkSystemInterfaceDescriptor: Codable {
    let systemInterfaceParameters: OcaBlob
    let myNetworkAddress: OcaNetworkAddress
}
