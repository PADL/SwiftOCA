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
import AsyncAlgorithms

extension NetService: Identifiable {
    public typealias ID = String
    
    public var id: ID {
        return name
    }
}

extension Binding: Equatable where Value == NetService? {
    public static func == (lhs: Binding<Value>, rhs: Binding<Value>) -> Bool {
        lhs.wrappedValue?.id == rhs.wrappedValue?.id
    }
}

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

public struct OcaBonjourDiscoveryView: View {
    let udpBrowser = AES70Browser(serviceType: .udp)
    let tcpBrowser = AES70Browser(serviceType: .tcp)
    @State var services = [NetService]()
    @State var serviceSelection: NetService? = nil
    
    public init() {
    }
    
    public var body: some View {
        Group {
            NavigationView {
                List(services, selection: $serviceSelection) { service in
                    NavigationLink(destination: OcaBonjourDeviceView(service)) {
                        Text(service.name)
                    }
                }
            }.navigationViewStyle(.stack)
        }
            .task {
                for await result in chain(udpBrowser.channel, tcpBrowser.channel) {
                    switch result {
                    case .didFind(let netService):
                        services.append(netService)
                        break
                    case .didRemove(let netService):
                        services.removeAll(where: { $0 == netService })
                        break
                    case .didNotSearch(let error):
                        debugPrint("OcaBonjourDiscoveryView: \(error)")
                        break
                    }
                }
            }
    }
}
