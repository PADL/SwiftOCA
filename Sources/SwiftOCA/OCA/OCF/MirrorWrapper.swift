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

// we don't want to add public Equatable / Hashable conformances to Mirror, so wrap it.
public struct _MirrorWrapper: Equatable, Hashable {
    public let wrappedValue: Mirror

    public init(_ wrappedValue: Mirror) {
        self.wrappedValue = wrappedValue
    }

    public static func == (lhs: _MirrorWrapper, rhs: _MirrorWrapper) -> Bool {
        lhs.wrappedValue.description == rhs.wrappedValue.description
    }

    public func hash(into hasher: inout Hasher) {
        wrappedValue.description.hash(into: &hasher)
    }
}
