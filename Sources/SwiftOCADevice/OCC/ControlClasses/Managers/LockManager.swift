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

@OcaDeviceMethods
public class OcaLockManager: OcaManager {
  override open class var classID: OcaClassID { OcaClassID("1.3.14") }
  override open class var classVersion: OcaClassVersionNumber { 3 }

  private struct LockWaiterID: Hashable {
    let controller: OcaController.ID
    let target: OcaONo
  }

  private final class LockWaiter: @unchecked
  Sendable {
    private let continuation: CheckedContinuation<(), Error>
    var task: Task<(), Never>?

    init(continuation: CheckedContinuation<(), Error>) {
      self.continuation = continuation
    }

    func didLock() {
      continuation.resume(returning: ())
    }

    func didAbort() {
      continuation.resume(throwing: CancellationError())
    }

    deinit {
      task?.cancel()
    }
  }

  private var lockWaiters = [LockWaiterID: LockWaiter]()

  func remove(controller: OcaController) {
    for kv in lockWaiters.filter({ kv in
      kv.key.controller == controller.id
    }) {
      lockWaiters.removeValue(forKey: kv.key)
    }
  }

  // the lock manager's own methods are not subject to its locks
  @OcaDeviceMethod("3.1", name: "LockWait", access: .none)
  private func lockWait(
    _ parameters: SwiftOCA.OcaLockManager.LockWaitParameters,
    from controller: any OcaController
  ) async throws {
    try await lockWait(
      controller: controller,
      target: parameters.target,
      type: parameters.type,
      timeout: parameters.timeout
    )
  }

  @OcaDeviceMethod("3.2", name: "AbortWaits", access: .none, parameterNames: ["ONo"])
  private func abortWaits(_ oNo: OcaONo, from controller: any OcaController) async throws {
    try await abortWaits(controller: controller, oNo: oNo)
  }

  private func lockWait(
    controller: OcaController,
    target: OcaONo,
    type: OcaLockState,
    timeout: OcaTimeInterval
  ) async throws {
    guard type != .noLock else {
      throw Ocp1Error.status(.parameterError)
    }

    guard let target = await deviceDelegate?.resolve(objectNumber: target) else {
      throw Ocp1Error.status(.badONo)
    }

    let lockWaiterID = LockWaiterID(controller: controller.id, target: target.objectNumber)

    do {
      try await withThrowingTimeout(
        of: .seconds(timeout),
        clock: .continuous,
        operation: { @OcaDevice in
          try await withCheckedThrowingContinuation { continuation in
            let lockWaiter = LockWaiter(continuation: continuation)
            Task { @OcaDevice in self.lockWaiters[lockWaiterID] = lockWaiter }

            lockWaiter.task = Task { [weak self] in
              for await _ in target.lockStateSubject
                .filter({ $0.lockState == .noLock })
              {
                if await target.setLockState(to: type, controller: controller) {
                  lockWaiter.didLock()
                  break
                }
              }
            }
          }
        },
        onTimeout: { @OcaDevice [self] in
          lockWaiters[lockWaiterID]?.didAbort()
        }
      )
    } catch Ocp1Error.responseTimeout {
      throw Ocp1Error.status(.timeout)
    }

    lockWaiters.removeValue(forKey: lockWaiterID)
  }

  private func abortWaits(controller: OcaController, oNo target: OcaONo) async throws {
    let lockWaiterID = LockWaiterID(controller: controller.id, target: target)

    guard let lockWaiter = lockWaiters[lockWaiterID] else {
      throw Ocp1Error.status(.invalidRequest)
    }

    lockWaiter.didAbort()
    lockWaiters.removeValue(forKey: lockWaiterID)
  }


  public convenience init(deviceDelegate: OcaDevice? = nil) async throws {
    try await self.init(
      objectNumber: OcaLockManagerONo,
      role: "LockManager",
      deviceDelegate: deviceDelegate,
      addToRootBlock: true
    )
  }
}
