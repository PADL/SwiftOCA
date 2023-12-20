import Foundation

/// The internal state used by the encoders.
class BinaryEncodingState {
    private let config: BinaryCodingConfiguration
    private(set) var data: Data = .init()

    /// Whether the encoder has already encountered a variable-sized type.
    /// Depending on the strategy, types after variable-sized types may be
    /// disallowed.
    private var hasVariableSizedType: Bool = false
    /// The current coding path on the type level. Used to detect cycles
    /// (i.e. recursive or mutually recursive types), which are essentially
    /// recursive types.
    private var codingTypePath: [String] = []

    init(config: BinaryCodingConfiguration, data: Data = .init()) {
        self.config = config
        self.data = data
    }

    func encodeNil() throws {
        throw BinaryEncodingError.nilNotEncodable
    }

    func encodeInteger<Integer>(_ value: Integer) throws where Integer: FixedWidthInteger {
        try ensureNotAfterVariableSizedType()
        withUnsafeBytes(of: config.endianness.apply(value)) {
            data += $0
        }
    }

    func encode(_ value: String) throws {
        try ensureNotAfterVariableSizedType()

        let isVariableSizedType = config.stringTypeStrategy == .none
        if isVariableSizedType {
            try ensureVariableSizedTypeAllowed(value)
        }

        guard let encoded = value.data(using: .utf8) else {
            throw BinaryEncodingError.stringNotEncodable(value)
        }

        if config.stringTypeStrategy == .lengthTagged {
            let length = UInt16(value.count)
            try encodeInteger(length)
        }
        data += encoded
        if config.stringTypeStrategy == .nullTerminate {
            data.append(0)
        }

        if isVariableSizedType {
            hasVariableSizedType = true
        }
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
        try ensureNotAfterVariableSizedType()

        var isVariableSizedType = value is [Any] || value is Data
        if isVariableSizedType {
            try ensureVariableSizedTypeAllowed(value)
        }

        switch value {
        case let data as Data:
            self.data += data
        case let array as [Encodable]:
            if config.variableSizedTypeStrategy == .lengthTaggedArrays {
                if array.count > UInt16.max {
                    throw BinaryEncodingError.variableSizedTypeTooBig
                }
                try encodeInteger(UInt16(array.count))
                isVariableSizedType = false
            }
            fallthrough
        default:
            try withCodingTypePath(appending: [String(describing: type(of: value))]) {
                try value.encode(to: BinaryEncoderImpl(state: self, codingPath: codingPath))
            }
        }

        if isVariableSizedType {
            hasVariableSizedType = true
        }
    }

    private func withCodingTypePath(appending delta: [String], action: () throws -> ()) throws {
        codingTypePath += delta
        try ensureNonRecursiveCodingTypePath()
        try action()
        codingTypePath.removeLast(delta.count)
    }

    private func ensureVariableSizedTypeAllowed(_ value: any Encodable) throws {
        let strategy = config.variableSizedTypeStrategy
        guard strategy.allowsSingleVariableSizedType ||
            value is [Any] && strategy == .lengthTaggedArrays
        else {
            throw BinaryEncodingError.variableSizedTypeDisallowed
        }
    }

    private func ensureNotAfterVariableSizedType() throws {
        let strategy = config.variableSizedTypeStrategy
        guard strategy.allowsValuesAfterVariableSizedTypes
            || (strategy.allowsSingleVariableSizedType && !hasVariableSizedType)
        else {
            throw BinaryEncodingError.valueAfterVariableSizedTypeDisallowed
        }
    }

    private func ensureNonRecursiveCodingTypePath() throws {
        let strategy = config.variableSizedTypeStrategy
        guard strategy.allowsRecursiveTypes || Set(codingTypePath).count == codingTypePath.count
        else {
            throw BinaryEncodingError.recursiveTypeDisallowed
        }
    }

    func ensureOptionalAllowed() throws {
        let strategy = config.variableSizedTypeStrategy
        guard strategy.allowsOptionalTypes else {
            throw BinaryEncodingError.optionalTypeDisallowed
        }
    }
}
