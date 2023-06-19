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

struct OcaMatrixNavigationSplitView: OcaView {
    @StateObject var object: OcaMatrix
    @Environment(\.navigationPath) var oNoPath
    @State var members: OcaMatrix.SparseMembers?

    init(_ object: OcaRoot) {
        self._object = StateObject(wrappedValue: object as! OcaMatrix)
    }

    public var body: some View {
        Group {
            if let members {
                Grid() {
                    ForEach(0..<members.nX, id: \.self) { x in
                        GridRow {
                            ForEach(0..<members.nY, id: \.self) { y in
                                Group {
                                    if let object = members[x, y] {
                                        OcaNavigationLabel(object)
                                    } else {
                                        ProgressView()
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .task {
            do {
                let proxy = try await object.resolveProxy()
                members = try await object.resolveMembers(with: proxy)
            } catch {
                debugPrint("OcaMatrixNavigationSplitView: error \(error)")
            }
        }
    }
}
