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
import SwiftOCA
import SwiftUI

public struct OcaBonjourDeviceView: View {
    @State
    var connection: AES70OCP1Connection? = nil
    @State
    var isConnected = false
    @State
    var lastError: Error? = nil
    var service: NetService

    public init(_ service: NetService) {
        self.service = service
    }

    public var body: some View {
        Group {
            if isConnected {
                OcaRootBlockView(connection!)
                    .environment(\.lastError, $lastError)
            } else {
                ProgressView()
            }
        }.task {
            do {
                connection = try await AES70OCP1Connection(service)
                if let connection {
                    try await connection.connect()
                    self.isConnected = true
                }
            } catch is CancellationError {
            } catch {
                debugPrint("OcaBonjourDeviceView: error \(error)")
                lastError = error
            }
        }.onDisappear {
            Task { @MainActor in
                if let connection {
                    self.isConnected = false
                    try await connection.disconnect()
                    self.connection = nil
                }
            }
        }
        .alert(isPresented: Binding.constant(lastError != nil)) {
            Alert(
                title: Text("Error"),
                message: Text("\(lastError!.localizedDescription)"),
                dismissButton: .default(Text("OK")) { lastError = nil }
            )
        }
    }
}
