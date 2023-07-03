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

struct Ocp1KeepAlive1: Ocp1Message, Codable {
    let heartBeatTime: OcaUint16 // sec

    var messageSize: OcaUint32 { 2 }
}

struct Ocp1KeepAlive2: Ocp1Message, Codable {
    let heartBeatTime: OcaUint32 // msec

    var messageSize: OcaUint32 { 4 }
}

typealias Ocp1KeepAlive = Ocp1KeepAlive1
