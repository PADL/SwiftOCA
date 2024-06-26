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

@OcaDevice
public protocol OcaPortsRepresentable: OcaRoot {
  var ports: [OcaPort] { get set }
}

extension OcaPortsRepresentable {
  /// Unique identifier of input or output Port within a given Worker or Block class.
  /// Port numbers are ordinals starting at 1, and there are separate numbering spaces
  /// for input and output Ports.
  @OcaDevice
  func firstAvailablePortID(mode: OcaPortMode) -> OcaPortID {
    OcaPortID(
      mode: mode,
      index: 1 + (ports.filter { $0.id.mode == mode }.map(\.id.index).max() ?? 0)
    )
  }

  @OcaDevice
  func handleGetPortName(
    _ command: Ocp1Command,
    from controller: OcaController
  ) async throws -> OcaString {
    // because portID is a struct, but we only want a single
    let params: OcaGetPortNameParameters = try decodeCommand(command)
    try await ensureReadable(by: controller, command: command)
    guard let portName = ports.first(where: { $0.id == params.portID })?.name else {
      throw Ocp1Error.status(.parameterOutOfRange)
    }
    return portName
  }

  @OcaDevice
  func handleSetPortName(
    _ command: Ocp1Command,
    from controller: OcaController
  ) async throws {
    let params: OcaSetPortNameParameters = try decodeCommand(command)
    try await ensureWritable(by: controller, command: command)
    guard let index = ports.firstIndex(where: { $0.id == params.portID }) else {
      throw Ocp1Error.status(.parameterOutOfRange)
    }
    let port = ports[index]
    let newPort = OcaPort(owner: port.owner, id: port.id, name: params.name)
    ports.replaceSubrange(index...index, with: [newPort])
  }
}

public extension SwiftOCADevice.OcaBlock where ActionObject: OcaPortsRepresentable {
  func connect(
    _ outputs: [ActionObject],
    to inputs: [ActionObject],
    name: OcaString? = nil,
    addToBlock: Bool = true
  ) async throws {
    precondition(outputs.count == inputs.count)

    for i in 0..<outputs.count {
      let name = name ?? "\(outputs[i].role) -> \(inputs[i].role)"

      let outputPort = OcaPort(
        owner: objectNumber,
        id: outputs[i].firstAvailablePortID(mode: .output),
        name: "\(name) [Output Port \(i + 1)]"
      )
      outputs[i].ports.append(outputPort)

      let inputPort = OcaPort(
        owner: objectNumber,
        id: inputs[i].firstAvailablePortID(mode: .input),
        name: "\(name) [Input Port \(i + 1)]"
      )
      inputs[i].ports.append(inputPort)

      let signalPath = OcaSignalPath(sourcePort: outputPort, sinkPort: inputPort)
      _ = try await add(signalPath: signalPath)

      if addToBlock, outputs[i] != self, !actionObjects.contains(outputs[i]) {
        try await add(actionObject: outputs[i])
      }
    }
  }

  func connect(
    _ output: ActionObject,
    to input: ActionObject,
    width: Int = 1,
    name: OcaString? = nil,
    addToBlock: Bool = true
  ) async throws {
    try await connect(
      Array(repeating: output, count: width),
      to: Array(repeating: input, count: width),
      name: name,
      addToBlock: addToBlock
    )
  }
}

@OcaDevice
public protocol OcaPortClockMapRepresentable: OcaRoot {
  var portClockMap: OcaMap<OcaPortID, OcaPortClockMapEntry> { get set }
}

extension OcaPortClockMapRepresentable {
  func handleSetPortClockMapEntry(
    _ command: Ocp1Command,
    from controller: OcaController
  ) async throws {
    let parameters: OcaSetPortClockMapEntryParameters = try decodeCommand(command)
    try await ensureWritable(by: controller, command: command)
    portClockMap[parameters.portID] = parameters.portClockMapEntry
  }

  func handleDeletePortClockMapEntry(
    _ command: Ocp1Command,
    from controller: OcaController
  ) async throws {
    let portID: OcaPortID = try decodeCommand(command)
    try await ensureWritable(by: controller, command: command)
    portClockMap.removeValue(forKey: portID)
  }

  func handleGetPortClockMapEntry(
    _ command: Ocp1Command,
    from controller: OcaController
  ) async throws -> OcaPortClockMapEntry {
    let portID: OcaPortID = try decodeCommand(command)
    try await ensureReadable(by: controller, command: command)
    guard let portClockMapEntry = portClockMap[portID] else {
      throw Ocp1Error.status(.invalidRequest)
    }
    return portClockMapEntry
  }
}
