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
        struct InterospectableIterator<T: Collection>: IteratorProtocol {
            typealias Element = T.Element
            var iterator: T.Iterator
            var position = 0

            init(_ elements: T) { iterator = elements.makeIterator() }

            mutating func next() -> Element? {
                position += 1
                return iterator.next()
            }
        }

        let scalarCount = try Int(decodeInteger(UInt16.self))
        var iterator = InterospectableIterator(data)
        var scalars = [Unicode.Scalar]()
        var utf8Decoder = UTF8()

        for _ in 0..<scalarCount {
            switch utf8Decoder.decode(&iterator) {
            case let .scalarValue(v):
                scalars.append(v)
            case .emptyInput:
                throw Ocp1Error.pduTooShort
            case .error:
                throw Ocp1Error.stringNotDecodable([UInt8](data))
            }
        }

        data.removeFirst(iterator.position)

        return String(String.UnicodeScalarView(scalars))
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
