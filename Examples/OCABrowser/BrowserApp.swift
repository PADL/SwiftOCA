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
import SwiftOCA
import SwiftOCAUI
import SwiftUI

#if os(macOS)
class BonjourBrowser: ObservableObject {
    let udpBrowser = AES70Browser(serviceType: .udp)
    let tcpBrowser = AES70Browser(serviceType: .tcp)
    @Published
    var services = [NetService]()

    init() {
        Task {
            await withTaskGroup(of: Void.self) { [self] group in
                group.addTask { [self] in
                    for await result in udpBrowser.channel {
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
                group.addTask { [self] in
                    for await result in tcpBrowser.channel {
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
    }

    @MainActor
    func service(with id: NetService.ID?) -> NetService? {
        guard let id else { return nil }
        return services.first(where: { $0.id == id })
    }
}
#endif

@main
struct SwiftOCABrowser: App {
    @Environment(\.refresh)
    private var refresh
    @Environment(\.openWindow)
    private var openWindow
    #if os(macOS)
    @StateObject
    var browser = BonjourBrowser()
    #endif

    @SceneBuilder
    var body: some Scene {
        Group {
            WindowGroup(id: "BonjourBrowser", for: String.self) { serviceID in
                #if os(macOS)
                if let service = browser.service(with: serviceID.wrappedValue) {
                    OcaBonjourDeviceView(service)
                } else {
                    Text("Select a device from the File menu").font(.title)
                }
                #elseif os(iOS)
                OcaBonjourDiscoveryView()
                #endif
            }
        }
        .commands {
            #if os(macOS)
            CommandGroup(replacing: .newItem) {
                Menu("Connect") {
                    ForEach(browser.services, id: \.id) { service in
                        Button(service.name) {
                            openWindow(id: "BonjourBrowser", value: service.id)
                        }
                    }
                }
            }
            #endif
            CommandGroup(replacing: .toolbar) {
                Button("Refresh") {
                    Task {
                        await refresh?()
                    }
                }.keyboardShortcut("R")
            }
        }
    }
}
