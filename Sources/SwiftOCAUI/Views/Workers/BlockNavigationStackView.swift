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

struct OcaBlockNavigationStackView: OcaView {
    @StateObject var object: OcaBlock
    @Environment(\.navigationPath) var oNoPath
    @Environment(\.lastError) var lastError
    @State var members: [OcaRoot]?
    @State var membersMap: [OcaONo:OcaRoot]?
    @State var selectedONo: OcaONo? = nil

    init(_ object: OcaRoot) {
        self._object = StateObject(wrappedValue: object as! OcaBlock)
    }

    public var body: some View {
        Group {
            if let members {
                if members.hasContainerMembers {
                    NavigationStack(path: oNoPath) {
                        List(members, selection: $selectedONo) { member in
                            NavigationLink(value: member.objectNumber) {
                                OcaNavigationLabel(member)
                            }
                        }
                        .navigationDestination(for: OcaONo.self) { oNo in
                            if let member = self.membersMap![oNo] {
                                OcaDetailView(member)
                            }
                        }
                    }
                } else if members.allMembersAreViewRepresentable {
                    Grid {
                        Group {
                            GridRow {
                                ForEach(members, id: \.self.id) { member in
                                    OcaNavigationLabel(member)
                                }
                            }
                            GridRow {
                                ForEach(members, id: \.self.id) { member in
                                    OcaDetailView(member)
                                }
                            }
                        }.frame(width: 100)
                    }
                } else {
                    VStack {
                        ForEach(members, id: \.self.id) { member in
                            OcaPropertyTableView(member)
                                .frame(maxHeight: .infinity)
                                .scrollDisabled(true)
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .task {
            do {
                members = try await object.resolveMembers()
                membersMap = members?.map
            } catch {
                debugPrint("OcaNavigationStackView: error \(error)")
                lastError.wrappedValue = error
            }
        }
    }
}
