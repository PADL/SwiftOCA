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

import SwiftUI
import SwiftOCA

extension OcaBlock {
}

public struct OcaBlockView: OcaView {
    @StateObject var object: OcaRoot

    public init(_ connection: AES70OCP1Connection, object: OcaObjectIdentification) {
        self._object = StateObject(wrappedValue: connection.resolve(object: object) as! OcaBlock )
    }

    public var body: some View {
        Text(String(format: "%02X", object.objectNumber))
    }
}

// https://www.swiftbysundell.com/articles/switching-between-swiftui-hstack-vstack/
struct DynamicStack<Content: View>: View {
    var horizontalAlignment = HorizontalAlignment.center
    var verticalAlignment = VerticalAlignment.center
    var spacing: CGFloat?
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            Group {
                if proxy.size.width > proxy.size.height {
                    HStack(
                        alignment: verticalAlignment,
                        spacing: spacing,
                        content: content
                    )
                } else {
                    VStack(
                        alignment: horizontalAlignment,
                        spacing: spacing,
                        content: content
                    )
                }
            }
        }
    }
}
