//
// Copyright (c) 2026 PADL Software Pty Ltd
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

@_spi(SwiftOCAPrivate) import SwiftOCA

/// Every `OcaMethodDescription` a client class declares, by class, for the naming oracle
/// and the device sweep. Written from the sources; `ClientMethodDescriptionTests`
/// checks it against them, so a descriptor missing here fails.
enum ClientMethodDescriptions {
  typealias Entry = (name: String, description: OcaAnyMethodDescription)

  static let all: [(type: OcaRoot.Type, descriptors: [Entry])] = [
    (Aes67OcaMediaTransportApplication.self, [
      ("getEndpointDelayConstraints", Aes67OcaMediaTransportApplication.getEndpointDelayConstraints.erased),
      ("getPresentationTimeOffsetConstraints", Aes67OcaMediaTransportApplication.getPresentationTimeOffsetConstraints.erased),
      ("configureEndpointFromSDP", Aes67OcaMediaTransportApplication.configureEndpointFromSDP.erased),
    ]),
    (Aes67OcaMediaTransportSessionAgent.self, [
      ("getSIPParameterRecord", Aes67OcaMediaTransportSessionAgent.getSIPParameterRecord.erased),
      ("setSIPParameterRecord", Aes67OcaMediaTransportSessionAgent.setSIPParameterRecord.erased),
      ("getSIPParameter", Aes67OcaMediaTransportSessionAgent.getSIPParameter.erased),
      ("setSIPParameter", Aes67OcaMediaTransportSessionAgent.setSIPParameter.erased),
    ]),
    (Aes67StreamEndpointRegistry.self, [
      ("getRegistryEntry", Aes67StreamEndpointRegistry.getRegistryEntry.erased),
      ("addRegistryEntry", Aes67StreamEndpointRegistry.addRegistryEntry.erased),
      ("setRegistryEntry", Aes67StreamEndpointRegistry.setRegistryEntry.erased),
      ("deleteRegistryEntry", Aes67StreamEndpointRegistry.deleteRegistryEntry.erased),
      ("addRegistryEntriesFromSDP", Aes67StreamEndpointRegistry.addRegistryEntriesFromSDP.erased),
    ]),
    (DanteOcaMediaTransportApplication.self, [
      ("getChannelEndpoint", DanteOcaMediaTransportApplication.getChannelEndpoint.erased),
      ("setChannelEndpoint", DanteOcaMediaTransportApplication.setChannelEndpoint.erased),
      ("clearChannelEndpoint", DanteOcaMediaTransportApplication.clearChannelEndpoint.erased),
      ("addChannelEndpoint", DanteOcaMediaTransportApplication.addChannelEndpoint.erased),
      ("deleteChannelEndpoint", DanteOcaMediaTransportApplication.deleteChannelEndpoint.erased),
    ]),
    (OcaAgent.self, [
      ("getPath", OcaAgent.getPath.erased),
    ]),
    (OcaApplicationNetwork.self, [
      ("control", OcaApplicationNetwork.control.erased),
      ("getPath", OcaApplicationNetwork.getPath.erased),
    ]),
    (OcaCounterNotifier.self, [
      ("getLastUpdate", OcaCounterNotifier.getLastUpdate.erased),
    ]),
    (OcaCounterSetAgent.self, [
      ("getCounter", OcaCounterSetAgent.getCounter.erased),
      ("attachCounterNotifier", OcaCounterSetAgent.attachCounterNotifier.erased),
      ("detachCounterNotifier", OcaCounterSetAgent.detachCounterNotifier.erased),
      ("resetCounterSet", OcaCounterSetAgent.resetCounterSet.erased),
      ("resetCounter", OcaCounterSetAgent.resetCounter.erased),
    ]),
    (OcaGroup.self, [
      ("getMembers", OcaGroup.getMembers.erased),
      ("setMembers", OcaGroup.setMembers.erased),
      ("getGroupController", OcaGroup.getGroupController.erased),
      ("addMember", OcaGroup.addMember.erased),
      ("deleteMember", OcaGroup.deleteMember.erased),
    ]),
    (OcaMediaClock3.self, [
      ("getCurrentRate", OcaMediaClock3.getCurrentRate.erased),
      ("setCurrentRate", OcaMediaClock3.setCurrentRate.erased),
    ]),
    (OcaMediaTransportApplication.self, [
      ("addPort", OcaMediaTransportApplication.addPort.erased),
      ("deletePort", OcaMediaTransportApplication.deletePort.erased),
      ("getPortName", OcaMediaTransportApplication.getPortName.erased),
      ("setPortName", OcaMediaTransportApplication.setPortName.erased),
      ("setPortClockMapEntry", OcaMediaTransportApplication.setPortClockMapEntry.erased),
      ("deletePortClockMapEntry", OcaMediaTransportApplication.deletePortClockMapEntry.erased),
      ("getPortClockMapEntry", OcaMediaTransportApplication.getPortClockMapEntry.erased),
      ("getMaxEndpointCounts", OcaMediaTransportApplication.getMaxEndpointCounts.erased),
      ("getMediaStreamModeCapability", OcaMediaTransportApplication.getMediaStreamModeCapability.erased),
      ("getEndpoint", OcaMediaTransportApplication.getEndpoint.erased),
      ("getEndpointStatus", OcaMediaTransportApplication.getEndpointStatus.erased),
      ("addEndpoint", OcaMediaTransportApplication.addEndpoint.erased),
      ("deleteEndpoint", OcaMediaTransportApplication.deleteEndpoint.erased),
      ("applyEndpointCommand", OcaMediaTransportApplication.applyEndpointCommand.erased),
      ("setEndpointUserLabel", OcaMediaTransportApplication.setEndpointUserLabel.erased),
      ("setEndpointMediaStreamMode", OcaMediaTransportApplication.setEndpointMediaStreamMode.erased),
      ("setEndpointChannelMap", OcaMediaTransportApplication.setEndpointChannelMap.erased),
      ("setEndpointAlignmentLevel", OcaMediaTransportApplication.setEndpointAlignmentLevel.erased),
      ("getEndpointTimeSource", OcaMediaTransportApplication.getEndpointTimeSource.erased),
      ("setEndpointAdaptationData", OcaMediaTransportApplication.setEndpointAdaptationData.erased),
      ("getEndpointCounterSet", OcaMediaTransportApplication.getEndpointCounterSet.erased),
      ("getEndpointCounter", OcaMediaTransportApplication.getEndpointCounter.erased),
      ("attachEndpointCounterNotifier", OcaMediaTransportApplication.attachEndpointCounterNotifier.erased),
      ("detachEndpointCounterNotifier", OcaMediaTransportApplication.detachEndpointCounterNotifier.erased),
      ("resetEndpointCounterSet", OcaMediaTransportApplication.resetEndpointCounterSet.erased),
    ]),
    (OcaMediaTransportNetwork.self, [
      ("getPortName", OcaMediaTransportNetwork.getPortName.erased),
      ("setPortName", OcaMediaTransportNetwork.setPortName.erased),
      ("getSourceConnectors", OcaMediaTransportNetwork.getSourceConnectors.erased),
      ("getSourceConnector", OcaMediaTransportNetwork.getSourceConnector.erased),
      ("getSinkConnectors", OcaMediaTransportNetwork.getSinkConnectors.erased),
      ("getSinkConnector", OcaMediaTransportNetwork.getSinkConnector.erased),
      ("getConnectorsStatuses", OcaMediaTransportNetwork.getConnectorsStatuses.erased),
      ("getConnectorStatus", OcaMediaTransportNetwork.getConnectorStatus.erased),
      ("addSourceConnector", OcaMediaTransportNetwork.addSourceConnector.erased),
      ("addSinkConnector", OcaMediaTransportNetwork.addSinkConnector.erased),
      ("controlConnector", OcaMediaTransportNetwork.controlConnector.erased),
      ("setSourceConnectorPinMap", OcaMediaTransportNetwork.setSourceConnectorPinMap.erased),
      ("setSinkConnectorPinMap", OcaMediaTransportNetwork.setSinkConnectorPinMap.erased),
      ("setConnectorConnection", OcaMediaTransportNetwork.setConnectorConnection.erased),
      ("setConnectorCoding", OcaMediaTransportNetwork.setConnectorCoding.erased),
      ("setConnectorAlignmentLevel", OcaMediaTransportNetwork.setConnectorAlignmentLevel.erased),
      ("setConnectorAlignmentGain", OcaMediaTransportNetwork.setConnectorAlignmentGain.erased),
      ("deleteConnector", OcaMediaTransportNetwork.deleteConnector.erased),
    ]),
    (OcaMediaTransportSessionAgent.self, [
      ("getSession", OcaMediaTransportSessionAgent.getSession.erased),
      ("addSession", OcaMediaTransportSessionAgent.addSession.erased),
      ("configureSession", OcaMediaTransportSessionAgent.configureSession.erased),
      ("deleteSession", OcaMediaTransportSessionAgent.deleteSession.erased),
      ("resetSession", OcaMediaTransportSessionAgent.resetSession.erased),
      ("setStreamingEnabled", OcaMediaTransportSessionAgent.setStreamingEnabled.erased),
      ("startStreaming", OcaMediaTransportSessionAgent.startStreaming.erased),
      ("stopStreaming", OcaMediaTransportSessionAgent.stopStreaming.erased),
      ("getSessionStatus", OcaMediaTransportSessionAgent.getSessionStatus.erased),
      ("addConnection", OcaMediaTransportSessionAgent.addConnection.erased),
      ("configureConnection", OcaMediaTransportSessionAgent.configureConnection.erased),
      ("deleteConnection", OcaMediaTransportSessionAgent.deleteConnection.erased),
      ("deleteConnections", OcaMediaTransportSessionAgent.deleteConnections.erased),
    ]),
    (OcaNetworkApplication.self, [
      ("getPath", OcaNetworkApplication.getPath.erased),
      ("getCounter", OcaNetworkApplication.getCounter.erased),
      ("attachCounterNotifier", OcaNetworkApplication.attachCounterNotifier.erased),
      ("detachCounterNotifier", OcaNetworkApplication.detachCounterNotifier.erased),
      ("resetCounters", OcaNetworkApplication.resetCounters.erased),
    ]),
    (OcaNetworkInterface.self, [
      ("getPath", OcaNetworkInterface.getPath.erased),
      ("getCounter", OcaNetworkInterface.getCounter.erased),
      ("attachCounterNotifier", OcaNetworkInterface.attachCounterNotifier.erased),
      ("detachCounterNotifier", OcaNetworkInterface.detachCounterNotifier.erased),
      ("resetCounters", OcaNetworkInterface.resetCounters.erased),
      ("applyCommand", OcaNetworkInterface.applyCommand.erased),
    ]),
    (OcaRoot.self, [
      ("getLockable", OcaRoot.getLockable.erased),
      ("getRole", OcaRoot.getRole.erased),
      ("getLockState", OcaRoot.getLockState.erased),
      ("getClassIdentification", OcaRoot.getClassIdentification.erased),
      ("setLockNoReadWrite", OcaRoot.setLockNoReadWrite.erased),
      ("unlock", OcaRoot.unlock.erased),
      ("setLockNoWrite", OcaRoot.setLockNoWrite.erased),
    ]),
    (OcaTimeSource.self, [
      ("reset", OcaTimeSource.reset.erased),
    ]),
    (OcaWorker.self, [
      ("addPort", OcaWorker.addPort.erased),
      ("deletePort", OcaWorker.deletePort.erased),
      ("getPortName", OcaWorker.getPortName.erased),
      ("setPortName", OcaWorker.setPortName.erased),
      ("getPath", OcaWorker.getPath.erased),
      ("getPortClockMapEntry", OcaWorker.getPortClockMapEntry.erased),
      ("setPortClockMapEntry", OcaWorker.setPortClockMapEntry.erased),
      ("deletePortClockMapEntry", OcaWorker.deletePortClockMapEntry.erased),
    ]),
  ]
}
