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
      ("getPath", OcaAgent.Methods.getPath.erased),
    ]),
    (OcaApplicationNetwork.self, [
      ("getPath", OcaApplicationNetwork.Methods.getPath.erased),
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
    (OcaGroup.self, [
      ("getMembers", OcaGroup.Methods.getMembers.erased),
      ("setMembers", OcaGroup.Methods.setMembers.erased),
      ("getGroupController", OcaGroup.Methods.getGroupController.erased),
      ("addMember", OcaGroup.Methods.addMember.erased),
      ("deleteMember", OcaGroup.Methods.deleteMember.erased),
    ]),
    (OcaMediaClock3.self, [
      ("getCurrentRate", OcaMediaClock3.Methods.getCurrentRate.erased),
      ("setCurrentRate", OcaMediaClock3.Methods.setCurrentRate.erased),
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
    ]),
    (OcaNetworkInterface.self, [
      ("getPath", OcaNetworkInterface.Methods.getPath.erased),
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
    (OcaTimeSource.self, [
      ("reset", OcaTimeSource.Methods.reset.erased),
    ]),
    (OcaWorker.self, [
      ("getPath", OcaWorker.Methods.getPath.erased),
    ]),
  ]
}
