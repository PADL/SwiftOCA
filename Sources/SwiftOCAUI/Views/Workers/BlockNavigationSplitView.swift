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

struct OcaBlockNavigationSplitView: OcaView {
    @EnvironmentObject
    var connection: AES70OCP1Connection
    @Environment(\.navigationPath)
    var oNoPath
    @Environment(\.lastError)
    var lastError
    @StateObject
    var object: OcaBlock
    @State
    var members: [OcaRoot]?
    @State
    var membersMap: [OcaONo: OcaRoot]?
    @State
    var selectedONo: OcaONo? = nil

    init(_ object: OcaRoot) {
        _object = StateObject(wrappedValue: object as! OcaBlock)
    }

    var selectedObject: OcaRoot? {
        guard let selectedONo = selectedONo,
              let membersMap,
              let object = membersMap[selectedONo]
        else {
            return nil
        }

        return object
    }

    public var body: some View {
        Group {
            if let members {
                NavigationSplitView {
                    List(members, selection: $selectedONo) { member in
                        Group {
                            OcaNavigationLabel(member)
                        }
                    }
                } detail: {
                    Group {
                        if let selectedObject = selectedObject {
                            OcaDetailView(selectedObject)
                        }
                    }
                    .id(selectedONo)
                }
            } else {
                ProgressView()
            }
        }
        .task {
            do {
                members = try await object.resolveActionObjects()

                if object.objectNumber == OcaRootBlockONo,
                   !(members?.contains(connection.deviceManager) ?? false)
                {
                    members?.append(connection.deviceManager)
                }
                membersMap = members?.map
            } catch {
                debugPrint("OcaNavigationSplitView: error \(error) when resolving members")
                lastError.wrappedValue = error
            }
        }
    }
}
