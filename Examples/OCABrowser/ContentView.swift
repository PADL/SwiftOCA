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
import SwiftOCAUI

struct ContentView: View {
    @EnvironmentObject var connection: AES70OCP1Connection
    let id = OcaObjectIdentification(oNo: 0x9008, classIdentification: OcaMute.classIdentification)

    var body: some View {
        OcaRootBlockView(connection)
    }
}
