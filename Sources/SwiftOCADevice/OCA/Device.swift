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
import AsyncExtensions
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Logging
import SwiftOCA

public protocol OcaDeviceEventDelegate: AnyObject, Sendable {
  func onEvent(
    _ event: OcaEvent,
    parameters: Data
  ) async

  func onControllerExpiry(_ controller: OcaController) async
}

@globalActor
public actor OcaDevice {
  public nonisolated static let DefaultTimeout = Duration.seconds(5)
  public static let shared = OcaDevice()

  public private(set) var rootBlock: OcaBlock<OcaRoot>!
  public private(set) var subscriptionManager: OcaSubscriptionManager!
  public private(set) var deviceManager: OcaDeviceManager!

  var objects = [OcaONo: OcaRoot]()
  var peerToPeerGroupers = [OcaONo: _OcaPeerToPeerGrouperNotifiable]()
  var nextObjectNumber: OcaONo = OcaMaximumReservedONo + 1
  var endpoints = [OcaDeviceEndpoint]()
  var logger = Logger(label: "com.padl.SwiftOCADevice")

  weak var eventDelegate: OcaDeviceEventDelegate?
  weak var connectionBroker: OcaConnectionBroker? = _OcaDefaultConnectionBroker.shared
  weak var datasetStorageProvider: OcaDatasetStorageProvider?

  public func allocateObjectNumber() -> OcaONo {
    repeat {
      nextObjectNumber += 1
    } while objects[nextObjectNumber] != nil

    return nextObjectNumber - 1
  }

  public func initializeDefaultObjects(deviceManager: OcaDeviceManager? = nil) async throws {
    rootBlock = try await OcaBlock(
      objectNumber: OcaRootBlockONo,
      role: "",
      deviceDelegate: self,
      addToRootBlock: false
    )
    subscriptionManager = try await OcaSubscriptionManager(deviceDelegate: self)
    Task { @OcaDevice in await rootBlock.type = 1 }
    if let deviceManager {
      self.deviceManager = deviceManager
    } else {
      self.deviceManager = try await OcaDeviceManager(deviceDelegate: self)
    }
  }

  public func add(endpoint: OcaDeviceEndpoint) async throws {
    guard !endpoints.contains(where: { $0 === endpoint })
    else {
      throw Ocp1Error.endpointAlreadyRegistered
    }
    endpoints.append(endpoint)
  }

  public func remove(endpoint: OcaDeviceEndpoint) async throws {
    guard endpoints.contains(where: { $0 === endpoint })
    else {
      throw Ocp1Error.endpointNotRegistered
    }
    endpoints.removeAll { $0 === endpoint }
  }

  public func unlockAll(controller: OcaController) async {
    if let lockManager = resolve(objectNumber: OcaLockManagerONo) as? OcaLockManager {
      await lockManager.remove(controller: controller)
    }
    for object in objects.values {
      try? await object.unlock(controller: controller)
    }
  }

  public func register(object: some OcaRoot, addToRootBlock: Bool = true) async throws {
    precondition(
      object.objectNumber != OcaInvalidONo,
      "cannot register object with invalid ONo"
    )
    guard objects[object.objectNumber] == nil else {
      logger
        .warning(
          "attempted to register duplicate object \(object), existing object \(objects[object.objectNumber]!)"
        )
      throw Ocp1Error.duplicateObject(object.objectNumber)
    }
    objects[object.objectNumber] = object
    if addToRootBlock {
      precondition(object.objectNumber != OcaRootBlockONo)
      try await rootBlock.add(actionObject: object)
    }
    if object is OcaManager, let deviceManager, deviceManager != object {
      let classIdentification = await object.objectIdentification.classIdentification
      let managerDescriptor = OcaManagerDescriptor(
        objectNumber: object.objectNumber,
        name: object.description,
        classID: classIdentification.classID,
        classVersion: classIdentification.classVersion
      )
      Task { @OcaDevice in deviceManager.managers.append(managerDescriptor) }
    }
    if let object = object as? _OcaPeerToPeerGrouperNotifiable {
      peerToPeerGroupers[object.objectNumber] = object
    }
  }

  public func deregister(objectNumber: OcaONo) async throws {
    guard let object = objects[objectNumber] else {
      throw Ocp1Error.invalidObject(objectNumber)
    }
    try await deregister(object: object)
  }

  public func deregister(object: some OcaRoot) async throws {
    precondition(object != deviceManager)
    precondition(object != subscriptionManager)
    precondition(
      object.objectNumber != OcaInvalidONo,
      "cannot deregister object with invalid ONo"
    )
    precondition(
      objects[object.objectNumber] != nil,
      "this object was not registered with this device"
    )
    if object is OcaManager, let deviceManager, deviceManager != object {
      Task { @OcaDevice in
        deviceManager.managers.removeAll(where: { $0.objectNumber == object.objectNumber })
      }
    }
    if let object = object as? OcaOwnable,
       let owner = await objects[object.owner] as? OcaBlock
    {
      try await owner.delete(actionObject: owner)
    }
    objects[object.objectNumber] = nil
    peerToPeerGroupers[object.objectNumber] = nil
  }

  private func _makeExtendedStatusError(
    command: Ocp1Command,
    extendedStatus: Ocp1ExtendedStatus? = nil
  )
    -> [Ocp1Extension]?
  {
    if command.extendedStatusSupported,
       let extendedStatus,
       let extensionData: Data = try? Ocp1Encoder()
       .encode(extendedStatus)
    {
      [Ocp1Extension(
        extensionID: OcaExtendedStatusExtensionID,
        extensionData: OcaBlob(extensionData)
      )]
    } else {
      nil
    }
  }

  public func handleCommand(
    _ command: Ocp1Command,
    timeout: Duration = .zero,
    from controller: any OcaController
  ) async -> Ocp1Response {
    let object = objects[command.targetONo]
    do {
      guard let object else {
        throw Ocp1Error.status(.badONo)
      }

      return try await withThrowingTimeout(of: timeout, clock: .continuous) {
        if command.methodID.defLevel > 1,
           let peerToPeerObject = object as? any OcaGroupPeerToPeerMember
        {
          try await peerToPeerObject.handleCommandForEachPeerToPeerMember(
            command,
            from: controller
          )
        } else {
          try await object.handleCommand(command, from: controller)
        }
      }
    } catch let Ocp1Error.status(status) {
      return .init(
        responseSize: 0,
        handle: command.handle,
        statusCode: status,
        extensions: _makeExtendedStatusError(command: command)
      )
    } catch let Ocp1Error.extendedStatus(extendedStatus) {
      return .init(
        responseSize: 0,
        handle: command.handle,
        statusCode: extendedStatus.statusCode,
        extensions: _makeExtendedStatusError(
          command: command,
          extendedStatus: extendedStatus.extendedStatus
        )
      )
    } catch Ocp1Error.invalidProxyMethodResponse {
      return .init(responseSize: 0, handle: command.handle, statusCode: .invalidRequest)
    } catch Ocp1Error.nilNotEncodable {
      return .init(responseSize: 0, handle: command.handle, statusCode: .processingFailed)
    } catch Ocp1Error.invalidObject {
      return .init(responseSize: 0, handle: command.handle, statusCode: .badONo)
    } catch {
      if let object {
        logger
          .warning(
            "failed to handle command \(command) on \(object) from controller \(controller): \(error)"
          )
      } else {
        logger
          .warning(
            "failed to handle command \(command) from controller \(controller): \(error)"
          )
      }
      return .init(responseSize: 0, handle: command.handle, statusCode: .deviceError)
    }
  }

  public func notifySubscribers(
    _ event: OcaEvent,
    parameters: OcaPropertyChangedEventData<some Codable & Sendable>
  ) async throws {
    try await notifySubscribers(
      event,
      parameters: Ocp1Encoder().encode(parameters)
    )
    if !peerToPeerGroupers.isEmpty {
      try await _notifyPeerToPeerGroupers(event, parameters: parameters)
    }
  }

  private func _notifyEventDelegate(
    _ event: OcaEvent,
    parameters: Data
  ) async throws {
    guard let eventDelegate else { return }
    await eventDelegate.onEvent(event, parameters: parameters)
  }

  private func _notifySubscriptionManager(
    _ event: OcaEvent,
    parameters: Data
  ) async throws {
    guard let subscriptionManager else { return }

    switch await subscriptionManager.state {
    case .eventsDisabled:
      await subscriptionManager
        .enqueueObjectChangedWhilstNotificationsDisabled(event.emitterONo)
    case .normal:
      for endpoint in endpoints {
        for controller in await endpoint.controllers {
          let controller = controller as! OcaControllerDefaultSubscribing

          try? await controller.notifySubscribers(event, parameters: parameters)
        }
      }
    }
  }

  public func notifySubscribers(
    _ event: OcaEvent,
    parameters: Data
  ) async throws {
    // if we are using a custom device manager, it may set properties prior to the subscription
    // manager being initialized
    assert(deviceManager == nil || subscriptionManager != nil)

    try await _notifyEventDelegate(event, parameters: parameters)
    try await _notifySubscriptionManager(event, parameters: parameters)
  }

  func notifySubscribers(_ event: OcaEvent) async throws {
    try await notifySubscribers(event, parameters: Data())
  }

  public func setEventDelegate(_ eventDelegate: OcaDeviceEventDelegate) {
    self.eventDelegate = eventDelegate
  }

  public func setConnectionBroker(_ connectionBroker: OcaConnectionBroker) {
    self.connectionBroker = connectionBroker
  }

  public func setDatasetStorageProvider(
    _ storageProvider: OcaDatasetStorageProvider
  ) {
    datasetStorageProvider = storageProvider
  }

  public func resolve<T: OcaRoot>(objectNumber: OcaONo) -> T? {
    objects[objectNumber] as? T
  }

  public func resolve<T: OcaRoot>(objectIdentification: OcaObjectIdentification) async -> T? {
    guard let object: T = resolve(objectNumber: objectIdentification.oNo) else {
      return nil
    }

    var classID: OcaClassID? = objectIdentification.classIdentification.classID

    repeat {
      var classVersion = OcaRoot.classVersion

      repeat {
        let id = OcaClassIdentification(classID: classID!, classVersion: classVersion)

        if await id == object.objectIdentification.classIdentification {
          return object
        }

        classVersion = classVersion - 1
      } while classVersion != 0

      classID = classID?.parent
    } while classID != nil

    return nil
  }
}
