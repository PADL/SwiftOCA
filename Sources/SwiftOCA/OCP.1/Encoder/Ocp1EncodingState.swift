import Foundation

/// The internal state used by the encoders.
class Ocp1EncodingState {
    private(set) var data: Data = .init()

    /// The current coding path on the type level. Used to detect cycles
    /// (i.e. recursive or mutually recursive types), which are essentially
    /// recursive types.
    private var codingTypePath: [String] = []

    init(data: Data = .init()) {
        self.data = data
    }

    func encodeNil() throws {
        throw Ocp1Error.nilNotEncodable
    }

    func encodeInteger<Integer>(_ value: Integer) throws where Integer: FixedWidthInteger {
        withUnsafeBytes(of: value.bigEndian) {
            data += $0
        }
    }

    func encode(_ value: String) throws {
        guard let encoded = value.data(using: .utf8) else {
            throw Ocp1Error.stringNotEncodable(value)
        }

        // AES70-3-2018: the Len part of the OcaString shall define the string length
        // (i.e. the number of Unicode codepoints), not the byte length.
        let length = UInt16(value.unicodeScalars.count)
        try encodeInteger(length)
        data += encoded
    }

    func encode(_ value: Bool) throws {
        try encodeInteger(value ? 1 as UInt8 : 0)
    }

    func encode(_ value: Double) throws {
        try encodeInteger(value.bitPattern)
    }

    func encode(_ value: Float) throws {
        try encodeInteger(value.bitPattern)
    }

    func encode(_ value: Int) throws {
        try encodeInteger(value)
    }

    func encode(_ value: Int8) throws {
        try encodeInteger(value)
    }

    func encode(_ value: Int16) throws {
        try encodeInteger(value)
    }

    func encode(_ value: Int32) throws {
        try encodeInteger(value)
    }

    func encode(_ value: Int64) throws {
        try encodeInteger(value)
    }

    func encode(_ value: UInt) throws {
        try encodeInteger(value)
    }

    func encode(_ value: UInt8) throws {
        try encodeInteger(value)
    }

    func encode(_ value: UInt16) throws {
        try encodeInteger(value)
    }

    func encode(_ value: UInt32) throws {
        try encodeInteger(value)
    }

    func encode(_ value: UInt64) throws {
        try encodeInteger(value)
    }

    func encode<T>(_ value: T, codingPath: [any CodingKey]) throws where T: Encodable {
        switch value {
        case let data as Data:
            self.data += data
        case let array as [Encodable]:
            if array.count > UInt16.max {
                throw Ocp1Error.arrayOrDataTooBig
            }
            try encodeInteger(UInt16(array.count))
            fallthrough
        default:
            try withCodingTypePath(appending: [String(describing: type(of: value))]) {
                try value.encode(to: Ocp1EncoderImpl(state: self, codingPath: codingPath))
            }
        }
    }

    private func withCodingTypePath(appending delta: [String], action: () throws -> ()) throws {
        codingTypePath += delta
        guard Set(codingTypePath).count == codingTypePath.count else {
            throw Ocp1Error.recursiveTypeDisallowed
        }
        try action()
        codingTypePath.removeLast(delta.count)
    }
}
