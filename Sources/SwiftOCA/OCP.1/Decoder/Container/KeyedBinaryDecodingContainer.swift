//
// Copyright (c) 2022 fwcd
// Portions (c) 2023-2024 PADL Software Pty Ltd
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//

struct KeyedOcp1DecodingContainer<Key>: KeyedDecodingContainerProtocol where Key: CodingKey {
    private let state: Ocp1DecodingState

    let codingPath: [any CodingKey]
    var allKeys: [Key] { [] }

    init(state: Ocp1DecodingState, codingPath: [any CodingKey]) {
        self.state = state
        self.codingPath = codingPath
    }

    func contains(_ key: Key) -> Bool {
        // Since the binary representation is untagged, we accept every key
        true
    }

    func nestedContainer<NestedKey>(
        keyedBy type: NestedKey.Type,
        forKey key: Key
    ) throws -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey {
        .init(KeyedOcp1DecodingContainer<NestedKey>(state: state, codingPath: codingPath + [key]))
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
        UnkeyedOcp1DecodingContainer(state: state, codingPath: codingPath, count: nil)
    }

    func superDecoder() throws -> any Decoder {
        Ocp1DecoderImpl(state: state, codingPath: codingPath)
    }

    func superDecoder(forKey key: Key) throws -> any Decoder {
        Ocp1DecoderImpl(state: state, codingPath: codingPath)
    }

    func decodeNil(forKey key: Key) throws -> Bool { try state.decodeNil() }

    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool { try state.decode(type) }

    func decode(_ type: String.Type, forKey key: Key) throws -> String { try state.decode(type) }

    func decode(_ type: Double.Type, forKey key: Key) throws -> Double { try state.decode(type) }

    func decode(_ type: Float.Type, forKey key: Key) throws -> Float { try state.decode(type) }

    func decode(_ type: Int.Type, forKey key: Key) throws -> Int { try state.decode(type) }

    func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 { try state.decode(type) }

    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 { try state.decode(type) }

    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 { try state.decode(type) }

    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 { try state.decode(type) }

    func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt { try state.decode(type) }

    func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 { try state.decode(type) }

    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 { try state.decode(type) }

    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 { try state.decode(type) }

    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 { try state.decode(type) }

    func decode<T>(_ type: T.Type, forKey key: Key) throws -> T
        where T: Decodable { try state.decode(type, codingPath: codingPath + [key]) }
}
