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

struct OcaNavigationStackView: View {
    @StateObject var object: OcaBlock
    @Binding var oNoPath: NavigationPath
    @State var members: [OcaRoot] = []
    @State var membersMap: [OcaONo:OcaRoot] = [:]
    @State var selectedONo: OcaONo? = nil

    public var body: some View {
        NavigationStack(path: $oNoPath) {
            List(members, selection: $selectedONo) { member in
                if let member = member as? OcaBlock {
                    //NavigationLink(member.navigationLabel, value: member.objectNumber)
                    OcaDetailView(member)

                } else {
                    OcaDetailView(member)
                }
            }
            /*
            .navigationDestination(for: OcaONo.self) { oNo in
                let object = self.membersMap[oNo]
                if let object = object as? OcaBlock {
                    //OcaNavigationStackView(object: object, oNoPath: $oNoPath)
                    OcaDetailView(object)
                } else if let object {
                    OcaDetailView(object)
                }
            }*/
        }
        /*
        .onChange(of: selectedONo) { newValue in
            oNoPath.append(newValue!)
        }
         */
        .task {
            members = (try? await object.resolveMembers()) ?? []
            membersMap = members.map
        }
    }
}
