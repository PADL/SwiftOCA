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

    mutating func encode<T>(_ value: T, forKey key: Key) throws
        where T: Encodable { try state.encode(value, codingPath: codingPath + [key]) }
}
