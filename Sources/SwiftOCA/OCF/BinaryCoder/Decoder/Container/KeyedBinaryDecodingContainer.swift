struct KeyedBinaryDecodingContainer<Key>: KeyedDecodingContainerProtocol where Key: CodingKey {
    private let state: BinaryDecodingState

    let codingPath: [any CodingKey]
    var allKeys: [Key] { [] }

    init(state: BinaryDecodingState, codingPath: [any CodingKey]) {
        self.state = state
        self.codingPath = codingPath
    }

    func contains(_ key: Key) -> Bool {
        // Since the binary representation is untagged, we accept every key
        true
    }

    func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey {
        .init(KeyedBinaryDecodingContainer<NestedKey>(state: state, codingPath: codingPath + [key]))
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
        UnkeyedBinaryDecodingContainer(state: state, codingPath: codingPath, count: nil)
    }

    func superDecoder() throws -> any Decoder {
        BinaryDecoderImpl(state: state, codingPath: codingPath)
    }

    func superDecoder(forKey key: Key) throws -> any Decoder {
        BinaryDecoderImpl(state: state, codingPath: codingPath)
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

    func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T : Decodable { try state.decode(type, codingPath: codingPath + [key]) }
}
