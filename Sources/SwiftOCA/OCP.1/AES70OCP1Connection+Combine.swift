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

#if canImport(Combine) || canImport(OpenCombine)
#if canImport(Combine)
import Combine
#endif
#if canImport(OpenCombine)
import OpenCombine
#endif

extension AES70OCP1Connection {
    // FIXME: for portability outside of Combine we could use a AsyncPassthroughSubject
    func suspendUntilConnected() async throws {
        try await withTimeout(seconds: connectionTimeout) {
            while await self.monitor == nil {
                var cancellables = Set<AnyCancellable>()
                
                await withCheckedContinuation { pop in
                    self.objectWillChange.sink { _ in
                        pop.resume()
                    }.store(in: &cancellables)
                }
            }
        }
    }
}
#endif
