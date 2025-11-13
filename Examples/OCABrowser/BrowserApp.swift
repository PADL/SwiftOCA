//
// Copyright (c) 2023-2025 PADL Software Pty Ltd
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
  let udpBrowser = try! OcaNetServiceBrowser(serviceType: .udp)
  let tcpBrowser = try! OcaNetServiceBrowser(serviceType: .tcp)
  @Published
  var services = [AnyOcaNetworkAdvertisingServiceInfo]()

  init() {
    Task {
      await withTaskGroup(of: Void.self) { [self] group in
        group.addTask { [self] in
          do {
            try await udpBrowser.start()
            for try await result in udpBrowser.browseResults {
              Task { @MainActor in
                switch result {
                case let .added(serviceInfo):
                  services.append(AnyOcaNetworkAdvertisingServiceInfo(serviceInfo))
                case let .removed(serviceInfo):
                  services.removeAll(where: { $0 == AnyOcaNetworkAdvertisingServiceInfo(serviceInfo) })
                }
              }
            }
          } catch {}
        }
        group.addTask { [self] in
          do {
            try await tcpBrowser.start()
            for try await result in tcpBrowser.browseResults {
              Task { @MainActor in
                switch result {
                case let .added(serviceInfo):
                  services.append(AnyOcaNetworkAdvertisingServiceInfo(serviceInfo))
                case let .removed(serviceInfo):
                  services.removeAll(where: { $0 == AnyOcaNetworkAdvertisingServiceInfo(serviceInfo) })
                }
              }
            }
          } catch {}
        }
      }
    }
  }

  @MainActor
  func service(with name: String?) -> AnyOcaNetworkAdvertisingServiceInfo? {
    guard let name else { return nil }
    return services.first(where: { $0.name == name })
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
          ForEach(browser.services, id: \.name) { service in
            Button(service.name) {
              openWindow(id: "BonjourBrowser", value: service.name)
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
