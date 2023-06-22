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
    @Environment(\.lastError) var lastError
    @State var members: OcaMatrix.SparseMembers?
    @State var membersMap: [OcaONo:OcaRoot]?
    @State var hasContainerMembers = false

    init(_ object: OcaRoot) {
        self._object = StateObject(wrappedValue: object as! OcaMatrix)
    }

    public var body: some View {
        NavigationStack(path: oNoPath) {
            Group {
                if let members {
                    Grid() {
                        GridRow {
                            ForEach(0..<members.nX, id: \.self) { x in
                                Text("\(x + 1)").font(.title)
                            }
                        }
                        ForEach(0..<members.nY, id: \.self) { y in
                            GridRow {
                                ForEach(0..<members.nX, id: \.self) { x in
                                    Group {
                                        if let member = members[x, y] {
                                            if hasContainerMembers {
                                                NavigationLink(value: member.objectNumber) {
                                                    OcaNavigationLabel(member)
                                                }
                                            } else {
                                                OcaDetailView(member)
                                            }
                                        } else {
                                            ProgressView()
                                        }
                                    }.padding(5)
                                }
                            }
                        }
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationDestination(for: OcaONo.self) { oNo in
                if let member = self.membersMap![oNo] {
                    OcaDetailView(member)
                }
            }
        }
        .task {
            do {
                members = try await object.resolveMembers()
                if let members {
                    membersMap = members.map
                    hasContainerMembers = members.hasContainerMembers
                } else {
                    membersMap = nil
                    hasContainerMembers = false
                }
            } catch {
                debugPrint("OcaMatrixNavigationSplitView: error \(error)")
                lastError.wrappedValue = error
            }
        }
    }
}
