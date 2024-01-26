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

public class OcaLockManager: OcaManager {
    override public class var classID: OcaClassID { OcaClassID("1.3.14") }
    override public class var classVersion: OcaClassVersionNumber { 3 }

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

    @OcaDevice
    func remove(controller: OcaController) {
        for kv in lockWaiters.filter({ kv in
            kv.key.controller == controller.id
        }) {
            lockWaiters.removeValue(forKey: kv.key)
        }
    }

    @OcaDevice
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
            try await withThrowingTimeout(of: .seconds(timeout)) {
                try await withCheckedThrowingContinuation { continuation in
                    let lockWaiter = LockWaiter(continuation: continuation)
                    self.lockWaiters[lockWaiterID] = lockWaiter

                    lockWaiter.task = Task {
                        for await _ in target.lockStateSubject
                            .filter({ $0.lockState == .noLock })
                        {
                            if target.setLockState(to: type, controller: controller) {
                                lockWaiter.didLock()
                                break
                            }
                        }
                    }
                }
            }
        } catch Ocp1Error.responseTimeout {
            lockWaiters[lockWaiterID]?.didAbort()
            throw Ocp1Error.status(.timeout)
        }

        lockWaiters.removeValue(forKey: lockWaiterID)
    }

    @OcaDevice
    private func abortWaits(controller: OcaController, oNo target: OcaONo) async throws {
        let lockWaiterID = LockWaiterID(controller: controller.id, target: target)

        guard let lockWaiter = lockWaiters[lockWaiterID] else {
            throw Ocp1Error.status(.invalidRequest)
        }

        lockWaiter.didAbort()
        lockWaiters.removeValue(forKey: lockWaiterID)
    }

    override public func handleCommand(
        _ command: Ocp1Command,
        from controller: OcaController
    ) async throws -> Ocp1Response {
        switch command.methodID {
        case OcaMethodID("3.1"):
            let params: SwiftOCA.OcaLockManager.LockWaitParameters = try decodeCommand(command)
            try await lockWait(
                controller: controller,
                target: params.target,
                type: params.type,
                timeout: params.timeout
            )
            return Ocp1Response()
        case OcaMethodID("3.2"):
            let oNo: OcaONo = try decodeCommand(command)
            try await abortWaits(controller: controller, oNo: oNo)
            return Ocp1Response()
        default:
            return try await super.handleCommand(command, from: controller)
        }
    }

    public convenience init(deviceDelegate: OcaDevice? = nil) async throws {
        try await self.init(
            objectNumber: OcaLockManagerONo,
            role: "Lock Manager",
            deviceDelegate: deviceDelegate,
            addToRootBlock: true
        )
    }
}
