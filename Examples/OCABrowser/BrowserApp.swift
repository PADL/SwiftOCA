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

import SwiftOCA
import SwiftOCAUI
import SwiftUI

private struct DeviceBrowserView: View {
  let broker: OcaConnectionBroker
  @State
  private var devices = [OcaConnectionBroker.DeviceIdentifier]()
  @State
  private var deviceSelection: OcaConnectionBroker.DeviceIdentifier? = nil

  var body: some View {
    NavigationSplitView {
      List(devices, selection: $deviceSelection) { device in
        VStack(alignment: .leading, spacing: 2) {
          Text(device.name)
            .font(.headline)
          Text(device.serviceType == .tcp ? "TCP" : "UDP")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .tag(device)
      }
      .navigationTitle("Devices")
    } detail: {
      if let deviceSelection {
        DeviceDetailView(broker: broker, deviceIdentifier: deviceSelection)
          .id(deviceSelection)
      } else {
        Text("Select a device").font(.title).foregroundStyle(.secondary)
      }
    }
    .task {
      for await event in await broker.events {
        switch event.eventType {
        case .deviceAdded:
          devices.append(event.deviceIdentifier)
        case .deviceRemoved:
          if deviceSelection == event.deviceIdentifier {
            deviceSelection = nil
          }
          devices.removeAll(where: { $0 == event.deviceIdentifier })
        case .deviceUpdated:
          if let index = devices.firstIndex(of: event.deviceIdentifier) {
            devices[index] = event.deviceIdentifier
          }
        default:
          break
        }
      }
    }
  }
}

private struct DeviceDetailView: View {
  let broker: OcaConnectionBroker
  let deviceIdentifier: OcaConnectionBroker.DeviceIdentifier
  @State
  private var connection: Ocp1Connection? = nil

  var body: some View {
    Group {
      if let connection {
        OcaRootBlockView(connection)
      } else {
        ProgressView()
      }
    }
    .navigationTitle(deviceIdentifier.name)
    .task {
      do {
        try await broker.connect(device: deviceIdentifier)
        connection = try await broker
          .withDeviceConnection(deviceIdentifier) { @Sendable connection in
            connection
          }
      } catch {
        debugPrint("DeviceDetailView: failed to connect to \(deviceIdentifier.name): \(error)")
      }
    }
  }
}

@main
struct SwiftOCABrowser: App {
  @State
  private var broker: OcaConnectionBroker? = nil

  var body: some Scene {
    WindowGroup {
      if let broker {
        DeviceBrowserView(broker: broker)
      } else {
        ProgressView()
          .task {
            broker = await OcaConnectionBroker(
              connectionOptions: Ocp1ConnectionOptions(flags: [
                .automaticReconnect,
                .refreshSubscriptionsOnReconnection,
                .retainObjectCacheAfterDisconnect,
              ])
            )
          }
      }
    }
    .commands {
      CommandGroup(replacing: .toolbar) {
        Button("Refresh") {}
          .keyboardShortcut("R")
      }
    }
  }
}
