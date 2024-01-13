import Foundation

/// The internal state used by the decoders.
class Ocp1DecodingState {
    private var data: Data

    var isAtEnd: Bool { data.isEmpty }

    init(data: Data) {
        self.data = data
    }

    func decodeNil() throws -> Bool {
        // Since we don't encode `nil`s, we just always return `false``
        false
    }

    func decode(_ type: Bool.Type) throws -> Bool {
        guard let byte = data.popFirst() else {
            throw Ocp1Error.pduTooShort
        }
        return byte != 0
    }

    func decode(_ type: String.Type) throws -> String {
        var raw = Data()
        // TODO: deal with actual number of Unicode code points
        let length = Int(try decodeInteger(UInt16.self))
        raw.append(data.prefix(length))
        guard raw.count == length else {
            throw Ocp1Error.pduTooShort
        }
        data.removeFirst(length)
        guard let value = String(data: raw, encoding: .utf8) else {
            throw Ocp1Error.stringNotDecodable(raw)
        }
        return value
    }

    func decodeInteger<Integer>(_ type: Integer.Type) throws -> Integer
        where Integer: FixedWidthInteger
    {
        let byteWidth = Integer.bitWidth / 8

        guard data.count >= byteWidth else {
            throw Ocp1Error.pduTooShort
        }

        let value = data.prefix(byteWidth).withUnsafeBytes {
            Integer(bigEndian: $0.loadUnaligned(as: Integer.self))
        }

        data.removeFirst(byteWidth)
        return value
    }

    func decode(_ type: Double.Type) throws -> Double {
        Double(bitPattern: try decodeInteger(UInt64.self))
    }

    func decode(_ type: Float.Type) throws -> Float {
        Float(bitPattern: try decodeInteger(UInt32.self))
    }

    func decode(_ type: Int.Type) throws -> Int {
        try decodeInteger(type)
    }

    func decode(_ type: Int8.Type) throws -> Int8 {
        try decodeInteger(type)
    }

    func decode(_ type: Int16.Type) throws -> Int16 {
        try decodeInteger(type)
    }

    func decode(_ type: Int32.Type) throws -> Int32 {
        try decodeInteger(type)
    }

    func decode(_ type: Int64.Type) throws -> Int64 {
        try decodeInteger(type)
    }

    func decode(_ type: UInt.Type) throws -> UInt {
        try decodeInteger(type)
    }

    func decode(_ type: UInt8.Type) throws -> UInt8 {
        try decodeInteger(type)
    }

    func decode(_ type: UInt16.Type) throws -> UInt16 {
        try decodeInteger(type)
    }

    func decode(_ type: UInt32.Type) throws -> UInt32 {
        try decodeInteger(type)
    }

    func decode(_ type: UInt64.Type) throws -> UInt64 {
        try decodeInteger(type)
    }

    func decode<T>(_ type: T.Type, codingPath: [any CodingKey]) throws -> T where T: Decodable {
        var count: Int? = nil
        if type is any ArrayRepresentable.Type {
            count = try Int(UInt16(from: Ocp1DecoderImpl(state: self, codingPath: [])))
        }
        return try T(from: Ocp1DecoderImpl(state: self, codingPath: codingPath, count: count))
    }
}
