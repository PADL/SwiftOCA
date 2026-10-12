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

@OcaDeviceClass
public class OcaLockManager: OcaManager {
  override open class var classID: OcaClassID { OcaClassID("1.3.14") }
  override open class var classVersion: OcaClassVersionNumber { 3 }

  private struct LockWaiterID: Hashable {
    let controller: OcaController.ID
    let target: OcaONo
  }

  // only ever touched on the OcaDevice actor
  private final class LockWaiter: @unchecked Sendable {
    private var continuation: CheckedContinuation<(), Error>?
    private var result: Result<(), Error>?
    var task: Task<(), Never>?

    // false if the wait ended before the call could suspend, which resumes it at once
    func suspend(_ continuation: CheckedContinuation<(), Error>) -> Bool {
      if let result {
        continuation.resume(with: result)
        return false
      }
      self.continuation = continuation
      return true
    }

    // false if the wait had already ended, so the lock just taken is not wanted
    @discardableResult
    func didLock() -> Bool {
      finish(with: .success(()))
    }

    func didAbort(with error: Error = CancellationError()) {
      finish(with: .failure(error))
    }

    // resumes the waiting call at most once and ends the task either way
    @discardableResult
    private func finish(with result: Result<(), Error>) -> Bool {
      guard self.result == nil else { return false }
      self.result = result
      continuation?.resume(with: result)
      continuation = nil
      task?.cancel()
      task = nil
      return true
    }
  }

  private var lockWaiters = [LockWaiterID: LockWaiter]()

  var lockWaiterCount: Int { lockWaiters.count }

  private func abort(_ lockWaiterID: LockWaiterID, with error: Error = CancellationError()) {
    lockWaiters.removeValue(forKey: lockWaiterID)?.didAbort(with: error)
  }

  func remove(controller: OcaController) {
    for lockWaiterID in lockWaiters.keys where lockWaiterID.controller == controller.id {
      abort(lockWaiterID)
    }
  }

  // the lock manager's own methods are not subject to its locks
  @OcaDeviceMethod(SwiftOCA.OcaLockManager.Methods.lockWait, access: .unchecked)
  private func lockWait(
    target: OcaONo,
    type: OcaLockState,
    timeout: OcaTimeInterval,
    from controller: any OcaController
  ) async throws {
    guard type != .noLock else {
      throw Ocp1Error.status(.parameterError)
    }

    guard let target = await deviceDelegate?.resolve(objectNumber: target) else {
      throw Ocp1Error.status(.badONo)
    }

    let lockWaiterID = LockWaiterID(controller: controller.id, target: target.objectNumber)
    let lockWaiter = LockWaiter()

    // a second wait by the same controller on the same target replaces the first
    abort(lockWaiterID)
    lockWaiters[lockWaiterID] = lockWaiter
    defer {
      if lockWaiters[lockWaiterID] === lockWaiter {
        lockWaiters.removeValue(forKey: lockWaiterID)
      }
      lockWaiter.didAbort()
    }

    do {
      try await withThrowingTimeout(
        of: .seconds(Double(timeout)),
        clock: .continuous,
        operation: { @OcaDevice in
          try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
              guard lockWaiter.suspend(continuation) else { return }

              lockWaiter.task = Task { @OcaDevice in
                for await _ in target.lockStateSubject
                  .filter({ $0.lockState == .noLock })
                {
                  guard !Task.isCancelled else { break }
                  if await target.setLockState(to: type, controller: controller) {
                    if !lockWaiter.didLock() {
                      _ = await target.setLockState(to: .noLock, controller: controller)
                    }
                    break
                  }
                }
              }
            }
          } onCancel: {
            Task { @OcaDevice in lockWaiter.didAbort() }
          }
        },
        onTimeout: { @OcaDevice in
          lockWaiter.didAbort(with: Ocp1Error.status(.timeout))
        }
      )
    } catch Ocp1Error.responseTimeout {
      throw Ocp1Error.status(.timeout)
    }
  }

  @OcaDeviceMethod(SwiftOCA.OcaLockManager.Methods.abortWaits, access: .unchecked)
  private func abortWaits(oNo: OcaONo, from controller: any OcaController) async throws {
    let lockWaiterID = LockWaiterID(controller: controller.id, target: oNo)

    guard lockWaiters[lockWaiterID] != nil else {
      throw Ocp1Error.status(.invalidRequest)
    }

    abort(lockWaiterID)
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
