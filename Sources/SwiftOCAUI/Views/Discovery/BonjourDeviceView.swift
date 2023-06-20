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

import Foundation
import SwiftUI
import SwiftOCA

struct OcaBonjourDeviceView: View {
    @State var connection: AES70OCP1Connection? = nil
    var service: NetService
    
    init(_ service: NetService) {
        self.service = service
    }
    
    var body: some View {
        Group {
            if let connection {
                OcaRootBlockView(connection)
            } else {
                ProgressView()
            }
        }.task {
            do {
                connection = try await AES70OCP1Connection(service)
                if let connection {
                    try await connection.connect()
                }
            } catch {
                debugPrint("OcaBonjourDeviceView: error \(error)")
            }
        }
    }
}
