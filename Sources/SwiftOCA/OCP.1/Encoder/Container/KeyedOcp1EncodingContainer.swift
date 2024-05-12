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

struct KeyedOcp1EncodingContainer<Key>: KeyedEncodingContainerProtocol where Key: CodingKey {
  private let state: Ocp1EncodingState

  let codingPath: [any CodingKey]

  init(state: Ocp1EncodingState, codingPath: [any CodingKey]) {
    self.state = state
    self.codingPath = codingPath
  }

  mutating func nestedContainer<NestedKey>(
    keyedBy keyType: NestedKey.Type,
    forKey key: Key
  ) -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey {
    .init(KeyedOcp1EncodingContainer<NestedKey>(state: state, codingPath: codingPath + [key]))
  }

  mutating func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
    UnkeyedOcp1EncodingContainer(state: state, codingPath: codingPath + [key])
  }

  mutating func superEncoder() -> Encoder {
    Ocp1EncoderImpl(state: state, codingPath: codingPath)
  }

  mutating func superEncoder(forKey key: Key) -> Encoder {
    Ocp1EncoderImpl(state: state, codingPath: codingPath)
  }

  mutating func encodeNil(forKey key: Key) throws { try state.encodeNil() }

  mutating func encode(_ value: Bool, forKey key: Key) throws { try state.encode(value) }

  mutating func encode(_ value: String, forKey key: Key) throws { try state.encode(value) }

  mutating func encode(_ value: Double, forKey key: Key) throws { try state.encode(value) }

  mutating func encode(_ value: Float, forKey key: Key) throws { try state.encode(value) }

  mutating func encode(_ value: Int, forKey key: Key) throws { try state.encode(value) }

  mutating func encode(_ value: Int8, forKey key: Key) throws { try state.encode(value) }

  mutating func encode(_ value: Int16, forKey key: Key) throws { try state.encode(value) }

  mutating func encode(_ value: Int32, forKey key: Key) throws { try state.encode(value) }

  mutating func encode(_ value: Int64, forKey key: Key) throws { try state.encode(value) }

  mutating func encode(_ value: UInt, forKey key: Key) throws { try state.encode(value) }

  mutating func encode(_ value: UInt8, forKey key: Key) throws { try state.encode(value) }

  mutating func encode(_ value: UInt16, forKey key: Key) throws { try state.encode(value) }

  mutating func encode(_ value: UInt32, forKey key: Key) throws { try state.encode(value) }

  mutating func encode(_ value: UInt64, forKey key: Key) throws { try state.encode(value) }

  mutating func encode(_ value: some Encodable, forKey key: Key) throws
  { try state.encode(value, codingPath: codingPath + [key]) }
}
