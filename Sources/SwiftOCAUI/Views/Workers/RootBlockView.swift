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

public struct OcaRootBlockView: OcaView {
    @StateObject var object: OcaBlock
    @State var oNoPath = NavigationPath()
    
    public init(_ connection: AES70OCP1Connection) {
        self._object = StateObject(wrappedValue: connection.rootBlock)
    }
    
    public init(_ object: OcaRoot) {
        self._object = StateObject(wrappedValue: object as! OcaBlock)
    }

    public var body: some View {
        OcaBlockNavigationSplitView(object)
            .environment(\.navigationPath, $oNoPath)
    }
}
