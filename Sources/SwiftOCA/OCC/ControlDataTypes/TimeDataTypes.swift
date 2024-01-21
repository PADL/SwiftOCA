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

import Foundation

public struct OcaTime: Codable, Sendable {
    public var negative: OcaBoolean
    public var seconds: OcaUint64
    public var nanoseconds: OcaUint32

    public init() {
        negative = false
        seconds = 0
        nanoseconds = 0
    }

    public init(negative: OcaBoolean, seconds: OcaUint64, nanoseconds: OcaUint32) {
        self.negative = negative
        self.seconds = seconds
        self.nanoseconds = nanoseconds
    }
}

public typealias OcaTimeInterval = TimeInterval

// TODO: check OcaTimeMode encoding
public enum OcaTimeMode: OcaUint8, Codable, Sendable {
    case absolute = 1
    case relative = 2
}

public typealias OcaTimeNTP = OcaUint64

public typealias OcaTimePTP = OcaTime
