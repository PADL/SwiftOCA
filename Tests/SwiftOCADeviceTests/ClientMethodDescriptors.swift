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
    (OcaAgent.self, [
      ("getPath", OcaAgent.getPath.erased),
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
    (OcaDeviceManager.self, [
      ("clearResetCause", OcaDeviceManager.clearResetCause.erased),
      ("setDeviceName", OcaDeviceManager.setDeviceName.erased),
      ("applyPatch", OcaDeviceManager.applyPatch.erased),
    ]),
    (OcaDeviceTimeManager.self, [
      ("getDeviceTimeNTP", OcaDeviceTimeManager.getDeviceTimeNTP.erased),
      ("setDeviceTimeNTP", OcaDeviceTimeManager.setDeviceTimeNTP.erased),
      ("getCurrentDeviceTimeSource", OcaDeviceTimeManager.getCurrentDeviceTimeSource.erased),
      ("setCurrentDeviceTimeSource", OcaDeviceTimeManager.setCurrentDeviceTimeSource.erased),
      ("getDeviceTime", OcaDeviceTimeManager.getDeviceTime.erased),
      ("setDeviceTime", OcaDeviceTimeManager.setDeviceTime.erased),
    ]),
    (OcaDiagnosticManager.self, [
      ("getLockStatus", OcaDiagnosticManager.getLockStatus.erased),
    ]),
    (OcaFirmwareManager.self, [
      ("startUpdateProcess", OcaFirmwareManager.startUpdateProcess.erased),
      ("beginActiveImageUpdate", OcaFirmwareManager.beginActiveImageUpdate.erased),
      ("addImageData", OcaFirmwareManager.addImageData.erased),
      ("verifyImage", OcaFirmwareManager.verifyImage.erased),
      ("endActiveImageUpdate", OcaFirmwareManager.endActiveImageUpdate.erased),
      ("beginPassiveComponentUpdate", OcaFirmwareManager.beginPassiveComponentUpdate.erased),
      ("endUpdateProcess", OcaFirmwareManager.endUpdateProcess.erased),
    ]),
    (OcaGroup.self, [
      ("getMembers", OcaGroup.getMembers.erased),
      ("setMembers", OcaGroup.setMembers.erased),
      ("getGroupController", OcaGroup.getGroupController.erased),
      ("addMember", OcaGroup.addMember.erased),
      ("deleteMember", OcaGroup.deleteMember.erased),
    ]),
    (OcaLockManager.self, [
      ("lockWait", OcaLockManager.lockWait.erased),
      ("abortWaits", OcaLockManager.abortWaits.erased),
    ]),
    (OcaMediaClock3.self, [
      ("getCurrentRate", OcaMediaClock3.getCurrentRate.erased),
      ("setCurrentRate", OcaMediaClock3.setCurrentRate.erased),
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
    (OcaPowerManager.self, [
      ("exchangePowerSupply", OcaPowerManager.exchangePowerSupply.erased),
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
    (OcaSecurityManager.self, [
      ("enableControlSecurity", OcaSecurityManager.enableControlSecurity.erased),
      ("disableControlSecurity", OcaSecurityManager.disableControlSecurity.erased),
      ("changePreSharedKey", OcaSecurityManager.changePreSharedKey.erased),
      ("addPreSharedKey", OcaSecurityManager.addPreSharedKey.erased),
      ("deletePreSharedKey", OcaSecurityManager.deletePreSharedKey.erased),
    ]),
    (OcaSubscriptionManager.self, [
      ("addSubscription", OcaSubscriptionManager.addSubscription.erased),
      ("removeSubscription", OcaSubscriptionManager.removeSubscription.erased),
      ("disableNotifications", OcaSubscriptionManager.disableNotifications.erased),
      ("reenableNotifications", OcaSubscriptionManager.reenableNotifications.erased),
      ("addPropertyChangeSubscription", OcaSubscriptionManager.addPropertyChangeSubscription.erased),
      ("removePropertyChangeSubscription", OcaSubscriptionManager.removePropertyChangeSubscription.erased),
      ("getMaximumSubscriberContextLength", OcaSubscriptionManager.getMaximumSubscriberContextLength.erased),
      ("addSubscription2", OcaSubscriptionManager.addSubscription2.erased),
      ("removeSubscription2", OcaSubscriptionManager.removeSubscription2.erased),
      ("addPropertyChangeSubscription2", OcaSubscriptionManager.addPropertyChangeSubscription2.erased),
      ("removePropertyChangeSubscription2", OcaSubscriptionManager.removePropertyChangeSubscription2.erased),
      ("addSubscription2List", OcaSubscriptionManager.addSubscription2List.erased),
      ("removeSubscription2List", OcaSubscriptionManager.removeSubscription2List.erased),
      ("addPropertyChangeSubscription2List", OcaSubscriptionManager.addPropertyChangeSubscription2List.erased),
      ("removePropertyChangeSubscription2List", OcaSubscriptionManager.removePropertyChangeSubscription2List.erased),
    ]),
    (OcaTimeSource.self, [
      ("reset", OcaTimeSource.reset.erased),
    ]),
  ]
}
