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

public struct OcaBonjourDiscoveryView: View {
  let udpBrowser = try! OcaNetServiceBrowser(serviceType: .udp)
  let tcpBrowser = try! OcaNetServiceBrowser(serviceType: .tcp)
  @State
  var services = [AnyOcaNetworkAdvertisingServiceInfo]()
  @State
  var serviceSelection: AnyOcaNetworkAdvertisingServiceInfo? = nil

  public init() {}

  public var body: some View {
    NavigationStack {
      List(services, id: \.name, selection: $serviceSelection) { service in
        NavigationLink(destination: OcaBonjourDeviceView(service)) {
          Text(service.name)
        }
      }
    }
    .task {
      await withTaskGroup(of: Void.self) { group in
        group.addTask {
          do {
            try await udpBrowser.start()
            for try await result in udpBrowser.browseResults {
              await MainActor.run {
                switch result {
                case let .added(serviceInfo):
                  services.append(AnyOcaNetworkAdvertisingServiceInfo(serviceInfo))
                case let .removed(serviceInfo):
                  services
                    .removeAll(where: { $0 == AnyOcaNetworkAdvertisingServiceInfo(serviceInfo) })
                }
              }
            }
          } catch {}
        }
        group.addTask {
          do {
            try await tcpBrowser.start()
            for try await result in tcpBrowser.browseResults {
              await MainActor.run {
                switch result {
                case let .added(serviceInfo):
                  services.append(AnyOcaNetworkAdvertisingServiceInfo(serviceInfo))
                case let .removed(serviceInfo):
                  services
                    .removeAll(where: { $0 == AnyOcaNetworkAdvertisingServiceInfo(serviceInfo) })
                }
              }
            }
          } catch {}
        }
      }
    }
  }
}
