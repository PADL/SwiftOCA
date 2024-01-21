//
// Copyright (c) 2024 PADL Software Pty Ltd
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

public typealias OcaComponent = OcaUint16

public struct OcaVersion: Codable, Sendable {
    public let major: OcaUint32
    public let minor: OcaUint32
    public let build: OcaUint32
    public let component: OcaComponent

    public init(major: OcaUint32, minor: OcaUint32, build: OcaUint32, component: OcaComponent) {
        self.major = major
        self.minor = minor
        self.build = build
        self.component = component
    }
}
