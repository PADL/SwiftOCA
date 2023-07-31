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

import SwiftOCA
import SwiftUI

extension OcaGenericBasicSensor: OcaViewRepresentable {
    public var viewType: any OcaView.Type {
        OcaGenericBasicSensorView<T>.self
    }
}

public struct OcaGenericBasicSensorView<T: Codable & Comparable>: OcaView {
    @StateObject
    var object: OcaGenericBasicSensor<T>

    public init(_ object: OcaRoot) {
        _object = StateObject(wrappedValue: object as! OcaGenericBasicSensor<T>)
    }

    public var body: some View {
        Text(String(describing: object.reading))
            .showProgressIfWaiting(object.reading)
    }
}

extension OcaBooleanSensor: OcaViewRepresentable {
    public var viewType: any OcaView.Type {
        OcaBooleanSensorView.self
    }
}

public struct OcaBooleanSensorView: OcaView {
    @StateObject
    var object: OcaBooleanSensor

    public init(_ object: OcaRoot) {
        _object = StateObject(wrappedValue: object as! OcaBooleanSensor)
    }

    public var body: some View {
        Text(String(describing: object.reading))
            .showProgressIfWaiting(object.reading)
    }
}
