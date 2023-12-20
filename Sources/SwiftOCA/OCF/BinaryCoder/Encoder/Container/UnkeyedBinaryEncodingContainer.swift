struct UnkeyedBinaryEncodingContainer: UnkeyedEncodingContainer {
    private let state: BinaryEncodingState
    private(set) var count: Int = 0

    let codingPath: [any CodingKey]

    init(state: BinaryEncodingState, codingPath: [any CodingKey]) {
        self.state = state
        self.codingPath = codingPath
    }

    mutating func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey {
        .init(KeyedBinaryEncodingContainer<NestedKey>(state: state, codingPath: codingPath))
    }

    mutating func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer {
        UnkeyedBinaryEncodingContainer(state: state, codingPath: codingPath)
    }

    mutating func superEncoder() -> Encoder {
        BinaryEncoderImpl(state: state, codingPath: codingPath)
    }

    mutating func encodeNil() throws {
        try state.encodeNil()
        count += 1
    }

    mutating func encode(_ value: Bool) throws {
        try state.encode(value)
        count += 1
    }

    mutating func encode(_ value: String) throws {
        try state.encode(value)
        count += 1
    }

    mutating func encode(_ value: Double) throws {
        try state.encode(value)
        count += 1
    }

    mutating func encode(_ value: Float) throws {
        try state.encode(value)
        count += 1
    }

    mutating func encode(_ value: Int) throws {
        try state.encode(value)
        count += 1
    }

    mutating func encode(_ value: Int8) throws {
        try state.encode(value)
        count += 1
    }

    mutating func encode(_ value: Int16) throws {
        try state.encode(value)
        count += 1
    }

    mutating func encode(_ value: Int32) throws {
        try state.encode(value)
        count += 1
    }

    mutating func encode(_ value: Int64) throws {
        try state.encode(value)
        count += 1
    }

    mutating func encode(_ value: UInt) throws {
        try state.encode(value)
        count += 1
    }

    mutating func encode(_ value: UInt8) throws {
        try state.encode(value)
        count += 1
    }

    mutating func encode(_ value: UInt16) throws {
        try state.encode(value)
        count += 1
    }

    mutating func encode(_ value: UInt32) throws {
        try state.encode(value)
        count += 1
    }

    mutating func encode(_ value: UInt64) throws {
        try state.encode(value)
        count += 1
    }

    mutating func encode<T>(_ value: T) throws where T: Encodable {
        try state.encode(value, codingPath: codingPath)
        count += 1
    }
}
