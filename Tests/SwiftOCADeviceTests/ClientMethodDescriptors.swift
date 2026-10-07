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

/// Every `OcaMethodDescriptor` a client class declares, by class, for the naming oracle
/// and the device sweep. Written from the sources; `ClientMethodDescriptorTests`
/// checks it against them, so a descriptor missing here fails.
enum ClientMethodDescriptors {
  typealias Entry = (name: String, descriptor: OcaAnyMethodDescriptor)

  static let all: [(type: OcaRoot.Type, descriptors: [Entry])] = [
    (Aes67OcaMediaTransportApplication.self, [
      ("getEndpointDelayConstraints", Aes67OcaMediaTransportApplication.Methods.getEndpointDelayConstraints.erased),
      ("getPresentationTimeOffsetConstraints", Aes67OcaMediaTransportApplication.Methods.getPresentationTimeOffsetConstraints.erased),
      ("configureEndpointFromSDP", Aes67OcaMediaTransportApplication.Methods.configureEndpointFromSDP.erased),
    ]),
    (Aes67OcaMediaTransportSessionAgent.self, [
      ("getSIPParameterRecord", Aes67OcaMediaTransportSessionAgent.Methods.getSIPParameterRecord.erased),
      ("setSIPParameterRecord", Aes67OcaMediaTransportSessionAgent.Methods.setSIPParameterRecord.erased),
      ("getSIPParameter", Aes67OcaMediaTransportSessionAgent.Methods.getSIPParameter.erased),
      ("setSIPParameter", Aes67OcaMediaTransportSessionAgent.Methods.setSIPParameter.erased),
    ]),
    (Aes67StreamEndpointRegistry.self, [
      ("getRegistryEntry", Aes67StreamEndpointRegistry.Methods.getRegistryEntry.erased),
      ("addRegistryEntry", Aes67StreamEndpointRegistry.Methods.addRegistryEntry.erased),
      ("setRegistryEntry", Aes67StreamEndpointRegistry.Methods.setRegistryEntry.erased),
      ("deleteRegistryEntry", Aes67StreamEndpointRegistry.Methods.deleteRegistryEntry.erased),
      ("addRegistryEntriesFromSDP", Aes67StreamEndpointRegistry.Methods.addRegistryEntriesFromSDP.erased),
    ]),
    (DanteOcaMediaTransportApplication.self, [
      ("getChannelEndpoint", DanteOcaMediaTransportApplication.Methods.getChannelEndpoint.erased),
      ("setChannelEndpoint", DanteOcaMediaTransportApplication.Methods.setChannelEndpoint.erased),
      ("clearChannelEndpoint", DanteOcaMediaTransportApplication.Methods.clearChannelEndpoint.erased),
      ("addChannelEndpoint", DanteOcaMediaTransportApplication.Methods.addChannelEndpoint.erased),
      ("deleteChannelEndpoint", DanteOcaMediaTransportApplication.Methods.deleteChannelEndpoint.erased),
    ]),
    (OcaAgent.self, [
      ("getPath", OcaAgent.Methods.getPath.erased),
    ]),
    (OcaApplicationNetwork.self, [
      ("control", OcaApplicationNetwork.Methods.control.erased),
      ("getPath", OcaApplicationNetwork.Methods.getPath.erased),
    ]),
    (OcaBlock.self, [
      ("getActionObjects", OcaBlock.Methods.getActionObjects.erased),
      ("getDatasetObjects", OcaBlock.Methods.getDatasetObjects.erased),
      ("constructActionObject", OcaBlock.Methods.constructActionObject.erased),
      ("constructBlockUsingFactory", OcaBlock.Methods.constructBlockUsingFactory.erased),
      ("deleteMember", OcaBlock.Methods.deleteMember.erased),
      ("getActionObjectsRecursive", OcaBlock.Methods.getActionObjectsRecursive.erased),
      ("addSignalPath", OcaBlock.Methods.addSignalPath.erased),
      ("deleteSignalPath", OcaBlock.Methods.deleteSignalPath.erased),
      ("getSignalPathsRecursive", OcaBlock.Methods.getSignalPathsRecursive.erased),
      ("applyParamSet", OcaBlock.Methods.applyParamSet.erased),
      ("getCurrentParamSetData", OcaBlock.Methods.getCurrentParamSetData.erased),
      ("storeCurrentParamSetData", OcaBlock.Methods.storeCurrentParamSetData.erased),
      ("findActionObjectsByRole", OcaBlock.Methods.findActionObjectsByRole.erased),
      ("findActionObjectsByRoleRecursive", OcaBlock.Methods.findActionObjectsByRoleRecursive.erased),
      ("findActionObjectsByLabelRecursive", OcaBlock.Methods.findActionObjectsByLabelRecursive.erased),
      ("findActionObjectsByRolePath", OcaBlock.Methods.findActionObjectsByRolePath.erased),
      ("applyParamDataset", OcaBlock.Methods.applyParamDataset.erased),
      ("storeCurrentParameterData", OcaBlock.Methods.storeCurrentParameterData.erased),
      ("fetchCurrentParameterData", OcaBlock.Methods.fetchCurrentParameterData.erased),
      ("applyParameterData", OcaBlock.Methods.applyParameterData.erased),
      ("constructDataset", OcaBlock.Methods.constructDataset.erased),
      ("duplicateDataset", OcaBlock.Methods.duplicateDataset.erased),
      ("getDatasetObjectsRecursive", OcaBlock.Methods.getDatasetObjectsRecursive.erased),
      ("findDatasets", OcaBlock.Methods.findDatasets.erased),
      ("findDatasetsRecursive", OcaBlock.Methods.findDatasetsRecursive.erased),
    ]),
    (OcaClassManager.self, [
      ("getControlClass", OcaClassManager.Methods.getControlClass.erased),
      ("getControlClasses", OcaClassManager.Methods.getControlClasses.erased),
    ]),
    (OcaCounterNotifier.self, [
      ("getLastUpdate", OcaCounterNotifier.Methods.getLastUpdate.erased),
    ]),
    (OcaCounterSetAgent.self, [
      ("getCounter", OcaCounterSetAgent.Methods.getCounter.erased),
      ("attachCounterNotifier", OcaCounterSetAgent.Methods.attachCounterNotifier.erased),
      ("detachCounterNotifier", OcaCounterSetAgent.Methods.detachCounterNotifier.erased),
      ("resetCounterSet", OcaCounterSetAgent.Methods.resetCounterSet.erased),
      ("resetCounter", OcaCounterSetAgent.Methods.resetCounter.erased),
    ]),
    (OcaDataset.self, [
      ("openRead", OcaDataset.Methods.openRead.erased),
      ("openWrite", OcaDataset.Methods.openWrite.erased),
      ("close", OcaDataset.Methods.close.erased),
      ("read", OcaDataset.Methods.read.erased),
      ("write", OcaDataset.Methods.write.erased),
      ("clear", OcaDataset.Methods.clear.erased),
      ("getDatasetSizes", OcaDataset.Methods.getDatasetSizes.erased),
    ]),
    (OcaDelayExtended.self, [
      ("getDelayValueConverted", OcaDelayExtended.Methods.getDelayValueConverted.erased),
    ]),
    (OcaDeviceManager.self, [
      ("clearResetCause", OcaDeviceManager.Methods.clearResetCause.erased),
      ("setDeviceName", OcaDeviceManager.Methods.setDeviceName.erased),
      ("applyPatch", OcaDeviceManager.Methods.applyPatch.erased),
    ]),
    (OcaDeviceTimeManager.self, [
      ("getDeviceTimeNTP", OcaDeviceTimeManager.Methods.getDeviceTimeNTP.erased),
      ("setDeviceTimeNTP", OcaDeviceTimeManager.Methods.setDeviceTimeNTP.erased),
      ("getCurrentDeviceTimeSource", OcaDeviceTimeManager.Methods.getCurrentDeviceTimeSource.erased),
      ("setCurrentDeviceTimeSource", OcaDeviceTimeManager.Methods.setCurrentDeviceTimeSource.erased),
      ("getDeviceTime", OcaDeviceTimeManager.Methods.getDeviceTime.erased),
      ("setDeviceTime", OcaDeviceTimeManager.Methods.setDeviceTime.erased),
    ]),
    (OcaDiagnosticManager.self, [
      ("getLockStatus", OcaDiagnosticManager.Methods.getLockStatus.erased),
    ]),
    (OcaDynamics.self, [
      ("setMultiple", OcaDynamics.Methods.setMultiple.erased),
    ]),
    (OcaDynamicsCurve.self, [
      ("getThresholds", OcaDynamicsCurve.Methods.getThresholds.erased),
      ("getSlopes", OcaDynamicsCurve.Methods.getSlopes.erased),
      ("getKneeParameters", OcaDynamicsCurve.Methods.getKneeParameters.erased),
      ("setMultiple", OcaDynamicsCurve.Methods.setMultiple.erased),
    ]),
    (OcaDynamicsDetector.self, [
      ("setMultiple", OcaDynamicsDetector.Methods.setMultiple.erased),
    ]),
    (OcaFilterArbitraryCurve.self, [
      ("setTransferFunction", OcaFilterArbitraryCurve.Methods.setTransferFunction.erased),
    ]),
    (OcaFilterClassical.self, [
      ("setMultiple", OcaFilterClassical.Methods.setMultiple.erased),
    ]),
    (OcaFilterParametric.self, [
      ("setMultiple", OcaFilterParametric.Methods.setMultiple.erased),
    ]),
    (OcaFilterPolynomial.self, [
      ("getCoefficients", OcaFilterPolynomial.Methods.getCoefficients.erased),
      ("setCoefficients", OcaFilterPolynomial.Methods.setCoefficients.erased),
    ]),
    (OcaFirmwareManager.self, [
      ("startUpdateProcess", OcaFirmwareManager.Methods.startUpdateProcess.erased),
      ("beginActiveImageUpdate", OcaFirmwareManager.Methods.beginActiveImageUpdate.erased),
      ("addImageData", OcaFirmwareManager.Methods.addImageData.erased),
      ("verifyImage", OcaFirmwareManager.Methods.verifyImage.erased),
      ("endActiveImageUpdate", OcaFirmwareManager.Methods.endActiveImageUpdate.erased),
      ("beginPassiveComponentUpdate", OcaFirmwareManager.Methods.beginPassiveComponentUpdate.erased),
      ("endUpdateProcess", OcaFirmwareManager.Methods.endUpdateProcess.erased),
    ]),
    (OcaGroup.self, [
      ("getMembers", OcaGroup.Methods.getMembers.erased),
      ("setMembers", OcaGroup.Methods.setMembers.erased),
      ("getGroupController", OcaGroup.Methods.getGroupController.erased),
      ("addMember", OcaGroup.Methods.addMember.erased),
      ("deleteMember", OcaGroup.Methods.deleteMember.erased),
    ]),
    (OcaLevelSensor.self, [
      ("getReading", OcaLevelSensor.Methods.getReading.erased),
    ]),
    (OcaLockManager.self, [
      ("lockWait", OcaLockManager.Methods.lockWait.erased),
      ("abortWaits", OcaLockManager.Methods.abortWaits.erased),
    ]),
    (OcaLog.self, [
      ("addLogRecord", OcaLog.Methods.addLogRecord.erased),
    ]),
    (OcaMatrix.self, [
      ("setCurrentXY", OcaMatrix.Methods.setCurrentXY.erased),
      ("getSize", OcaMatrix.Methods.getSize.erased),
      ("getMembers", OcaMatrix.Methods.getMembers.erased),
      ("getProxy", OcaMatrix.Methods.getProxy.erased),
      ("getMember", OcaMatrix.Methods.getMember.erased),
      ("setMember", OcaMatrix.Methods.setMember.erased),
      ("setCurrentXYLock", OcaMatrix.Methods.setCurrentXYLock.erased),
      ("unlockCurrent", OcaMatrix.Methods.unlockCurrent.erased),
    ]),
    (OcaMediaClock3.self, [
      ("getCurrentRate", OcaMediaClock3.Methods.getCurrentRate.erased),
      ("setCurrentRate", OcaMediaClock3.Methods.setCurrentRate.erased),
    ]),
    (OcaMediaTransportApplication.self, [
      ("addPort", OcaMediaTransportApplication.Methods.addPort.erased),
      ("deletePort", OcaMediaTransportApplication.Methods.deletePort.erased),
      ("getPortName", OcaMediaTransportApplication.Methods.getPortName.erased),
      ("setPortName", OcaMediaTransportApplication.Methods.setPortName.erased),
      ("setPortClockMapEntry", OcaMediaTransportApplication.Methods.setPortClockMapEntry.erased),
      ("deletePortClockMapEntry", OcaMediaTransportApplication.Methods.deletePortClockMapEntry.erased),
      ("getPortClockMapEntry", OcaMediaTransportApplication.Methods.getPortClockMapEntry.erased),
      ("getMaxEndpointCounts", OcaMediaTransportApplication.Methods.getMaxEndpointCounts.erased),
      ("getMediaStreamModeCapability", OcaMediaTransportApplication.Methods.getMediaStreamModeCapability.erased),
      ("getEndpoint", OcaMediaTransportApplication.Methods.getEndpoint.erased),
      ("getEndpointStatus", OcaMediaTransportApplication.Methods.getEndpointStatus.erased),
      ("addEndpoint", OcaMediaTransportApplication.Methods.addEndpoint.erased),
      ("deleteEndpoint", OcaMediaTransportApplication.Methods.deleteEndpoint.erased),
      ("applyEndpointCommand", OcaMediaTransportApplication.Methods.applyEndpointCommand.erased),
      ("setEndpointUserLabel", OcaMediaTransportApplication.Methods.setEndpointUserLabel.erased),
      ("setEndpointMediaStreamMode", OcaMediaTransportApplication.Methods.setEndpointMediaStreamMode.erased),
      ("setEndpointChannelMap", OcaMediaTransportApplication.Methods.setEndpointChannelMap.erased),
      ("setEndpointAlignmentLevel", OcaMediaTransportApplication.Methods.setEndpointAlignmentLevel.erased),
      ("getEndpointTimeSource", OcaMediaTransportApplication.Methods.getEndpointTimeSource.erased),
      ("setEndpointAdaptationData", OcaMediaTransportApplication.Methods.setEndpointAdaptationData.erased),
      ("getEndpointCounterSet", OcaMediaTransportApplication.Methods.getEndpointCounterSet.erased),
      ("getEndpointCounter", OcaMediaTransportApplication.Methods.getEndpointCounter.erased),
      ("attachEndpointCounterNotifier", OcaMediaTransportApplication.Methods.attachEndpointCounterNotifier.erased),
      ("detachEndpointCounterNotifier", OcaMediaTransportApplication.Methods.detachEndpointCounterNotifier.erased),
      ("resetEndpointCounterSet", OcaMediaTransportApplication.Methods.resetEndpointCounterSet.erased),
    ]),
    (OcaMediaTransportNetwork.self, [
      ("getPortName", OcaMediaTransportNetwork.Methods.getPortName.erased),
      ("setPortName", OcaMediaTransportNetwork.Methods.setPortName.erased),
      ("getSourceConnectors", OcaMediaTransportNetwork.Methods.getSourceConnectors.erased),
      ("getSourceConnector", OcaMediaTransportNetwork.Methods.getSourceConnector.erased),
      ("getSinkConnectors", OcaMediaTransportNetwork.Methods.getSinkConnectors.erased),
      ("getSinkConnector", OcaMediaTransportNetwork.Methods.getSinkConnector.erased),
      ("getConnectorsStatuses", OcaMediaTransportNetwork.Methods.getConnectorsStatuses.erased),
      ("getConnectorStatus", OcaMediaTransportNetwork.Methods.getConnectorStatus.erased),
      ("addSourceConnector", OcaMediaTransportNetwork.Methods.addSourceConnector.erased),
      ("addSinkConnector", OcaMediaTransportNetwork.Methods.addSinkConnector.erased),
      ("controlConnector", OcaMediaTransportNetwork.Methods.controlConnector.erased),
      ("setSourceConnectorPinMap", OcaMediaTransportNetwork.Methods.setSourceConnectorPinMap.erased),
      ("setSinkConnectorPinMap", OcaMediaTransportNetwork.Methods.setSinkConnectorPinMap.erased),
      ("setConnectorConnection", OcaMediaTransportNetwork.Methods.setConnectorConnection.erased),
      ("setConnectorCoding", OcaMediaTransportNetwork.Methods.setConnectorCoding.erased),
      ("setConnectorAlignmentLevel", OcaMediaTransportNetwork.Methods.setConnectorAlignmentLevel.erased),
      ("setConnectorAlignmentGain", OcaMediaTransportNetwork.Methods.setConnectorAlignmentGain.erased),
      ("deleteConnector", OcaMediaTransportNetwork.Methods.deleteConnector.erased),
    ]),
    (OcaMediaTransportSessionAgent.self, [
      ("getSession", OcaMediaTransportSessionAgent.Methods.getSession.erased),
      ("addSession", OcaMediaTransportSessionAgent.Methods.addSession.erased),
      ("configureSession", OcaMediaTransportSessionAgent.Methods.configureSession.erased),
      ("deleteSession", OcaMediaTransportSessionAgent.Methods.deleteSession.erased),
      ("resetSession", OcaMediaTransportSessionAgent.Methods.resetSession.erased),
      ("setStreamingEnabled", OcaMediaTransportSessionAgent.Methods.setStreamingEnabled.erased),
      ("startStreaming", OcaMediaTransportSessionAgent.Methods.startStreaming.erased),
      ("stopStreaming", OcaMediaTransportSessionAgent.Methods.stopStreaming.erased),
      ("getSessionStatus", OcaMediaTransportSessionAgent.Methods.getSessionStatus.erased),
      ("addConnection", OcaMediaTransportSessionAgent.Methods.addConnection.erased),
      ("configureConnection", OcaMediaTransportSessionAgent.Methods.configureConnection.erased),
      ("deleteConnection", OcaMediaTransportSessionAgent.Methods.deleteConnection.erased),
      ("deleteConnections", OcaMediaTransportSessionAgent.Methods.deleteConnections.erased),
    ]),
    (OcaNetworkApplication.self, [
      ("getPath", OcaNetworkApplication.Methods.getPath.erased),
      ("getCounter", OcaNetworkApplication.Methods.getCounter.erased),
      ("attachCounterNotifier", OcaNetworkApplication.Methods.attachCounterNotifier.erased),
      ("detachCounterNotifier", OcaNetworkApplication.Methods.detachCounterNotifier.erased),
      ("resetCounters", OcaNetworkApplication.Methods.resetCounters.erased),
    ]),
    (OcaNetworkInterface.self, [
      ("getPath", OcaNetworkInterface.Methods.getPath.erased),
      ("getCounter", OcaNetworkInterface.Methods.getCounter.erased),
      ("attachCounterNotifier", OcaNetworkInterface.Methods.attachCounterNotifier.erased),
      ("detachCounterNotifier", OcaNetworkInterface.Methods.detachCounterNotifier.erased),
      ("resetCounters", OcaNetworkInterface.Methods.resetCounters.erased),
      ("applyCommand", OcaNetworkInterface.Methods.applyCommand.erased),
    ]),
    (OcaPowerManager.self, [
      ("exchangePowerSupply", OcaPowerManager.Methods.exchangePowerSupply.erased),
    ]),
    (OcaPowerSensor.self, [
      ("getReading", OcaPowerSensor.Methods.getReading.erased),
    ]),
    (OcaRoot.self, [
      ("getLockable", OcaRoot.Methods.getLockable.erased),
      ("getRole", OcaRoot.Methods.getRole.erased),
      ("getLockState", OcaRoot.Methods.getLockState.erased),
      ("getClassIdentification", OcaRoot.Methods.getClassIdentification.erased),
      ("setLockNoReadWrite", OcaRoot.Methods.setLockNoReadWrite.erased),
      ("unlock", OcaRoot.Methods.unlock.erased),
      ("setLockNoWrite", OcaRoot.Methods.setLockNoWrite.erased),
    ]),
    (OcaSecurityManager.self, [
      ("enableControlSecurity", OcaSecurityManager.Methods.enableControlSecurity.erased),
      ("disableControlSecurity", OcaSecurityManager.Methods.disableControlSecurity.erased),
      ("changePreSharedKey", OcaSecurityManager.Methods.changePreSharedKey.erased),
      ("addPreSharedKey", OcaSecurityManager.Methods.addPreSharedKey.erased),
      ("deletePreSharedKey", OcaSecurityManager.Methods.deletePreSharedKey.erased),
    ]),
    (OcaSignalGenerator.self, [
      ("start", OcaSignalGenerator.Methods.start.erased),
      ("stop", OcaSignalGenerator.Methods.stop.erased),
      ("setMultiple", OcaSignalGenerator.Methods.setMultiple.erased),
    ]),
    (OcaSubscriptionManager.self, [
      ("addSubscription", OcaSubscriptionManager.Methods.addSubscription.erased),
      ("removeSubscription", OcaSubscriptionManager.Methods.removeSubscription.erased),
      ("disableNotifications", OcaSubscriptionManager.Methods.disableNotifications.erased),
      ("reEnableNotifications", OcaSubscriptionManager.Methods.reEnableNotifications.erased),
      ("addPropertyChangeSubscription", OcaSubscriptionManager.Methods.addPropertyChangeSubscription.erased),
      ("removePropertyChangeSubscription", OcaSubscriptionManager.Methods.removePropertyChangeSubscription.erased),
      ("getMaximumSubscriberContextLength", OcaSubscriptionManager.Methods.getMaximumSubscriberContextLength.erased),
      ("addSubscription2", OcaSubscriptionManager.Methods.addSubscription2.erased),
      ("removeSubscription2", OcaSubscriptionManager.Methods.removeSubscription2.erased),
      ("addPropertyChangeSubscription2", OcaSubscriptionManager.Methods.addPropertyChangeSubscription2.erased),
      ("removePropertyChangeSubscription2", OcaSubscriptionManager.Methods.removePropertyChangeSubscription2.erased),
      ("addSubscription2List", OcaSubscriptionManager.Methods.addSubscription2List.erased),
      ("removeSubscription2List", OcaSubscriptionManager.Methods.removeSubscription2List.erased),
      ("addPropertyChangeSubscription2List", OcaSubscriptionManager.Methods.addPropertyChangeSubscription2List.erased),
      ("removePropertyChangeSubscription2List", OcaSubscriptionManager.Methods.removePropertyChangeSubscription2List.erased),
    ]),
    (OcaTimeSource.self, [
      ("reset", OcaTimeSource.Methods.reset.erased),
    ]),
    (OcaWorker.self, [
      ("addPort", OcaWorker.Methods.addPort.erased),
      ("deletePort", OcaWorker.Methods.deletePort.erased),
      ("getPortName", OcaWorker.Methods.getPortName.erased),
      ("setPortName", OcaWorker.Methods.setPortName.erased),
      ("getPath", OcaWorker.Methods.getPath.erased),
      ("getPortClockMapEntry", OcaWorker.Methods.getPortClockMapEntry.erased),
      ("setPortClockMapEntry", OcaWorker.Methods.setPortClockMapEntry.erased),
      ("deletePortClockMapEntry", OcaWorker.Methods.deletePortClockMapEntry.erased),
    ]),
  ]
}
