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

import AsyncAlgorithms
import Foundation
import SwiftOCA
import SwiftUI

extension NetService: Identifiable {
    public typealias ID = String

    public var id: ID {
        "\(domain)$\(type)$\(name)$\(String(port))"
    }
}

public struct OcaBonjourDiscoveryView: View {
    let udpBrowser = OcaBrowser(serviceType: .udp)
    let tcpBrowser = OcaBrowser(serviceType: .tcp)
    @State
    var services = [NetService]()
    @State
    var serviceSelection: NetService? = nil

    public init() {}

    public var body: some View {
        NavigationStack {
            List(services, selection: $serviceSelection) { service in
                NavigationLink(destination: OcaBonjourDeviceView(service)) {
                    Text(service.name)
                }
            }
        }
        .task {
            for await result in merge(udpBrowser.channel, tcpBrowser.channel) {
                switch result {
                case let .didFind(netService):
                    services.append(netService)
                case let .didRemove(netService):
                    services.removeAll(where: { $0 == netService })
                case let .didNotSearch(error):
                    debugPrint("OcaBonjourDiscoveryView: \(error)")
                }
            }
        }
    }
}
