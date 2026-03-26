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

/// Renders a single OcaRoot member using its specialized view if available,
/// otherwise falls back to OcaPropertyTableView. Delegates to
/// OcaDetailView.contentView which uses OcaViewRepresentable dispatch.
private struct OcaMemberView: View {
  let object: OcaRoot

  var body: some View {
    OcaDetailView.contentView(object)
  }
}

/// Shown in the detail pane when a leaf-only block is selected in the sidebar.
/// Renders all leaf members together with their actual views (gain slider,
/// mute toggle, etc.) in a horizontal layout.
private struct OcaLeafBlockView: View {
  let block: OcaBlock
  @Environment(\.lastError)
  var lastError
  @State
  private var members: [OcaRoot]?

  var body: some View {
    VStack {
      if let members {
        ScrollView {
          OcaNavigationLabel(block).font(.title).padding()
          let rows = members.chunked(into: min(members.count, 4))
          Grid(alignment: .center, horizontalSpacing: 16, verticalSpacing: 16) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
              GridRow {
                ForEach(row) { member in
                  VStack {
                    OcaNavigationLabel(member)
                    OcaMemberView(object: member)
                  }
                }
              }
            }
          }
          .padding()
        }
      } else {
        ProgressView()
      }
    }
    .task {
      do {
        members = try await block.resolveActionObjects()
      } catch {
        debugPrint("OcaLeafBlockView: error \(error)")
        lastError.wrappedValue = error
      }
    }
  }
}

struct OcaBlockNavigationSplitView: OcaView {
  @Environment(\.connection)
  var connection: Ocp1Connection!
  @Environment(\.lastError)
  var lastError
  @State
  var object: OcaBlock
  @State
  var selectedONo: OcaONo? = nil
  /// Stack of blocks representing the drill-down path. The last element
  /// is the block whose members are currently shown in the sidebar.
  @State
  private var blockPath = [OcaBlock]()
  @State
  private var currentMembers: [OcaRoot]?

  init(_ object: OcaRoot) {
    _object = State(wrappedValue: object as! OcaBlock)
  }

  private var currentBlock: OcaBlock {
    blockPath.last ?? object
  }

  var body: some View {
    NavigationSplitView {
      Group {
        if let currentMembers {
          List(selection: $selectedONo) {
            ForEach(currentMembers) { member in
              HStack {
                OcaNavigationLabel(member)
                if member.isContainer {
                  Spacer()
                  Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
                }
              }
              .tag(member.objectNumber)
            }
          }
        } else {
          ProgressView()
        }
      }
      .navigationTitle(currentBlock.navigationLabel)
      .toolbar {
        ToolbarItem(placement: .navigation) {
          if !blockPath.isEmpty {
            Button {
              popBlock()
            } label: {
              Image(systemName: "chevron.left")
            }
          }
        }
      }
      .onChange(of: selectedONo) { _, newValue in
        guard let newValue,
              let member = findObject(newValue),
              member is OcaBlock
        else { return }
        // Only drill into blocks that have sub-blocks;
        // leaf-only blocks stay selected and show content in the detail pane
        Task {
          let children = try? await (member as! OcaBlock).resolveActionObjects()
          let hasSubBlocks = children?.contains(where: \.isContainer) ?? false
          if hasSubBlocks {
            pushBlock(member as! OcaBlock)
          }
        }
      }
    } detail: {
      if let selectedONo, let selectedObject = findObject(selectedONo) {
        if let block = selectedObject as? OcaBlock {
          OcaLeafBlockView(block: block)
            .id(selectedONo)
        } else {
          OcaMemberView(object: selectedObject)
            .id(selectedONo)
        }
      }
    }
    .task {
      await resolveMembers(for: object)
    }
  }

  private func pushBlock(_ block: OcaBlock) {
    selectedONo = nil
    blockPath.append(block)
    currentMembers = nil
    Task {
      await resolveMembers(for: block)
    }
  }

  private func popBlock() {
    guard !blockPath.isEmpty else { return }
    selectedONo = nil
    blockPath.removeLast()
    currentMembers = nil
    Task {
      await resolveMembers(for: currentBlock)
    }
  }

  private func resolveMembers(for block: OcaBlock) async {
    do {
      var members = try await block.resolveActionObjects()
      if block.objectNumber == OcaRootBlockONo,
         !(members.contains(where: { $0.objectNumber == OcaDeviceManagerONo }))
      {
        await members.append(connection.deviceManager)
      }
      currentMembers = members
    } catch {
      debugPrint("OcaBlockNavigationSplitView: error \(error)")
      lastError.wrappedValue = error
    }
  }

  private func findObject(_ oNo: OcaONo) -> OcaRoot? {
    currentMembers?.first(where: { $0.objectNumber == oNo })
  }
}
