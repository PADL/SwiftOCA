struct SingleValueBinaryEncodingContainer: SingleValueEncodingContainer {
    private let state: BinaryEncodingState

    let codingPath: [any CodingKey]

    init(state: BinaryEncodingState, codingPath: [any CodingKey]) {
        self.state = state
        self.codingPath = codingPath
    }

    mutating func encodeNil() throws { try state.encodeNil() }

    mutating func encode(_ value: Bool) throws { try state.encode(value) }

    mutating func encode(_ value: String) throws { try state.encode(value) }

    mutating func encode(_ value: Double) throws { try state.encode(value) }

    mutating func encode(_ value: Float) throws { try state.encode(value) }

    mutating func encode(_ value: Int) throws { try state.encode(value) }

    mutating func encode(_ value: Int8) throws { try state.encode(value) }

    mutating func encode(_ value: Int16) throws { try state.encode(value) }

    mutating func encode(_ value: Int32) throws { try state.encode(value) }

    mutating func encode(_ value: Int64) throws { try state.encode(value) }

    mutating func encode(_ value: UInt) throws { try state.encode(value) }

    mutating func encode(_ value: UInt8) throws { try state.encode(value) }

    mutating func encode(_ value: UInt16) throws { try state.encode(value) }

    mutating func encode(_ value: UInt32) throws { try state.encode(value) }

    mutating func encode(_ value: UInt64) throws { try state.encode(value) }

    mutating func encode<T>(_ value: T) throws
        where T: Encodable { try state.encode(value, codingPath: codingPath) }
}
