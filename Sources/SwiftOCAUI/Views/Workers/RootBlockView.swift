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

public struct OcaRootBlockView: View {
    @Environment(\.lastError)
    var lastError
    @StateObject
    var connection: AES70OCP1Connection
    @StateObject
    var object: OcaBlock
    @State
    var oNoPath = NavigationPath()

    public init(_ connection: AES70OCP1Connection) {
        _connection = StateObject(wrappedValue: connection)
        _object = StateObject(wrappedValue: connection.rootBlock)
    }

    public var body: some View {
        VStack {
            OcaBlockNavigationSplitView(object)
                .environment(\.navigationPath, $oNoPath)
                .environmentObject(connection)
        }
    }
}
