struct SingleValueOcp1DecodingContainer: SingleValueDecodingContainer {
    private let state: Ocp1DecodingState
    let codingPath: [any CodingKey]

    init(state: Ocp1DecodingState, codingPath: [any CodingKey] = []) {
        self.state = state
        self.codingPath = codingPath
    }

    func decodeNil() -> Bool { (try? state.decodeNil()) ?? false }

    func decode(_ type: Bool.Type) throws -> Bool { try state.decode(type) }

    func decode(_ type: String.Type) throws -> String { try state.decode(type) }

    func decode(_ type: Double.Type) throws -> Double { try state.decode(type) }

    func decode(_ type: Float.Type) throws -> Float { try state.decode(type) }

    func decode(_ type: Int.Type) throws -> Int { try state.decode(type) }

    func decode(_ type: Int8.Type) throws -> Int8 { try state.decode(type) }

    func decode(_ type: Int16.Type) throws -> Int16 { try state.decode(type) }

    func decode(_ type: Int32.Type) throws -> Int32 { try state.decode(type) }

    func decode(_ type: Int64.Type) throws -> Int64 { try state.decode(type) }

    func decode(_ type: UInt.Type) throws -> UInt { try state.decode(type) }

    func decode(_ type: UInt8.Type) throws -> UInt8 { try state.decode(type) }

    func decode(_ type: UInt16.Type) throws -> UInt16 { try state.decode(type) }

    func decode(_ type: UInt32.Type) throws -> UInt32 { try state.decode(type) }

    func decode(_ type: UInt64.Type) throws -> UInt64 { try state.decode(type) }

    func decode<T>(_ type: T.Type) throws -> T
        where T: Decodable { try state.decode(type, codingPath: codingPath) }
}
