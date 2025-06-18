//
// Copyright (c) 2025 PADL Software Pty Ltd
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

public typealias OcaIOSessionHandle = OcaUint32

package let OcaIONullSessionHandle: OcaIOSessionHandle = 0
package let OcaIOSingletonSessionHandle: OcaIOSessionHandle = 1

public struct OcaDatasetSearchResult: Codable, Sendable {
  public let object: OcaBlockMember
  public let name: OcaString
  public let type: OcaMimeType

  public init(object: OcaBlockMember, name: OcaString, type: OcaMimeType) {
    self.object = object
    self.name = name
    self.type = type
  }
}

public let OcaParamDatasetMimeType = "application/x-oca-param"
public let OcaPatchDatasetMimeType = "application/x-oca-patch"
