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

public struct OcaMediaClockRate: Codable, Sendable, Equatable {
    public let nominalRate: OcaFrequency
    public let pullRange: OcaFrequency
    public let accuracy: OcaFloat32
    public let jitterMax: OcaFloat32

    public init(
        nominalRate: OcaFrequency = 48000.0,
        pullRange: OcaFrequency = 0.0,
        accuracy: OcaFloat32 = 0.0,
        jitterMax: OcaFloat32 = 0.0
    ) {
        self.nominalRate = nominalRate
        self.pullRange = pullRange
        self.accuracy = accuracy
        self.jitterMax = jitterMax
    }
}

public enum OcaMediaClockAvailability: OcaUint8, Codable, Sendable {
    case unavailable = 0
    case available = 1
}

public enum OcaMediaClockType: OcaUint8, Codable, Sendable {
    case none = 0
    case `internal` = 1
    case network = 2
    case external = 3
}
