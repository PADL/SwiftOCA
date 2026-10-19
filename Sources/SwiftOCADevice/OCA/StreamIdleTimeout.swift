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

import Synchronization

/// How long a stream controller's read may wait for the controller's next message.
///
/// Until the controller agrees a heartbeat, a read times out after the endpoint's timeout.
/// Once it has, reads don't time out: the keepalive task expires the controller after three
/// missed heartbeats (AES70-3 6.4.2). A read timeout as long as the heartbeat would instead
/// drop a controller whose keepalives, sent every heartbeat, arrive a little late.
package final class OcaStreamIdleTimeout: Sendable {
  private let timeout: Duration
  private let heartbeatAgreed = Atomic<Bool>(false)

  package init(_ timeout: Duration) {
    self.timeout = timeout
  }

  /// The timeout for a read about to start, or zero for none.
  package var duration: Duration {
    isEnabled ? timeout : .zero
  }

  /// False once a heartbeat is agreed, including while a read that began before it waits.
  package var isEnabled: Bool {
    !heartbeatAgreed.load(ordering: .relaxed)
  }

  package func heartbeatTimeDidChange(to heartbeatTime: Duration) {
    heartbeatAgreed.store(heartbeatTime != .zero, ordering: .relaxed)
  }
}
