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

import Foundation
import SwiftUI
import SwiftOCA

private struct ShowProgressIfWaitingViewModifier<T: Codable>: ViewModifier {
    let state: OcaProperty<T>.State
    
    init(_ state: OcaProperty<T>.State) {
        self.state = state
    }
    
    func body(content: Content) -> some View {
        if state.isLoading {
            ProgressView()
        } else {
            content
        }
    }
}

extension View {
    public func showProgressIfWaiting<T: Codable>(_ state: OcaProperty<T>.State) -> some View {
        return self.modifier(ShowProgressIfWaitingViewModifier<T>(state))
    }
}
