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

public struct OcaList2D<T> {
    public let nX, nY: Int
    var items: Array<Array<T>>

    public init(nX: Int, nY: Int) {
        self.nX = nX
        self.nY = nY
        self.items = Array<Array<T>>()
        self.items.reserveCapacity(self.nX)
        for x in 0..<self.nX {
            self.items[Int(x)] = Array<T>()
            self.items[Int(x)].reserveCapacity(self.nY)
        }
    }
    
    public init(nX: OcaUint16, nY: OcaUint16) {
        self.init(nX: Int(nX), nY: Int(nY))
    }
    
    public func item(x: Int, y: Int) -> T {
        items[x][y]
    }

    public func item(x: OcaUint16, y: OcaUint16) -> T {
        item(x: Int(x), y: Int(y))
    }
}

extension OcaList2D: Codable where T: Codable {
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        self.nX = Int(try container.decode(OcaUint16.self))
        self.nY = Int(try container.decode(OcaUint16.self))
    
        self.items = Array<Array<T>>()
        self.items.reserveCapacity(Int(self.nX))
        for x in 0..<self.nX {
            self.items[Int(x)] = Array<T>()
            self.items[Int(x)].reserveCapacity(Int(self.nY))
            for y in 0..<self.nY {
                self.items[Int(x)][Int(y)] = try container.decode(T.self)
            }
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(OcaUint16(self.nX))
        try container.encode(OcaUint16(self.nY))
        for x in 0..<self.nX {
            for y in 0..<self.nY {
                try container.encode(self.items[x][y])
            }
        }
    }
}

extension OcaList2D: Equatable where T: Equatable {
}
