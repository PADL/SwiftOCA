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

protocol Ocp1ListRepresentable: Collection, Codable where Element: Codable {}

extension Array: Ocp1ListRepresentable where Element: Codable {
    typealias Element = Element
}

struct Ocp1MapItem<Key: Hashable & Codable, Value: Codable>: Codable, Hashable {
    static func == (lhs: Ocp1MapItem<Key, Value>, rhs: Ocp1MapItem<Key, Value>) -> Bool {
        guard lhs.key == rhs.key else {
            return false
        }

        return true
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(key)
    }

    var key: Key
    var value: Value
}

protocol Ocp1MapRepresentable<Key, Value>: Collection, Codable {
    associatedtype Key: Codable & Hashable
    associatedtype Value: Codable

    init(from: Ocp1DecoderImpl) throws
    func withMapItems(_ block: (Key, Value) throws -> ()) rethrows
}

extension Dictionary: Ocp1MapRepresentable where Key: Codable & Hashable, Value: Codable {
    private init(mapItemSet: Set<Ocp1MapItem<Key, Value>>) {
        self = Dictionary(uniqueKeysWithValues: mapItemSet.map {
            ($0.key, $0.value)
        })
    }

    init(from ocp1Decoder: Ocp1DecoderImpl) throws {
        let mapItemSet = try Set<Ocp1MapItem<Key, Value>>(from: ocp1Decoder)
        self.init(mapItemSet: mapItemSet)
    }

    func withMapItems(_ block: (Key, Value) throws -> ()) rethrows {
        for (key, value) in self {
            try block(key, value)
        }
    }
}

protocol Ocp1Array2DRepresentable<Element> {
    associatedtype Element: Codable
}

extension OcaArray2D: Ocp1Array2DRepresentable where Element: Codable {
    typealias Element = Element
}

// private API for SwiftOCADevice

@_spi(SwiftOCAPrivate)
public extension Encoder {
    var _isOcp1Encoder: Bool {
        self is Ocp1EncoderImpl
    }
}

@_spi(SwiftOCAPrivate)
public extension Decoder {
    var _isOcp1Decoder: Bool {
        self is Ocp1DecoderImpl
    }
}

public protocol Ocp1LongList {}
public protocol Ocp1ParametersReflectable: Codable {}

@_spi(SwiftOCAPrivate)
public func _ocp1ParameterCount(type: (some Any).Type) -> OcaUint8 {
    if type is Ocp1ParametersReflectable.Type {
        var count: OcaUint8 = 0
        _forEachField(of: type) { _, _, _, _ in
            count += 1
            return true
        }
        return count
    } else if type is OcaRoot.Placeholder.Type {
        return 0
    } else {
        return 1
    }
}

@_spi(SwiftOCAPrivate)
public func _ocp1ParameterCount(value: some Any) -> OcaUint8 {
    _ocp1ParameterCount(type: type(of: value))
}
