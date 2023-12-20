import Foundation

/// An encoder that encodes Swift structures to a flat binary representation.
public struct BinaryEncoder {
    private let config: BinaryCodingConfiguration

    public init(config: BinaryCodingConfiguration = .init()) {
        self.config = config
    }

    /// Encodes a value to a flat binary representation.
    public func encode<Value>(_ value: Value) throws -> Data where Value: Encodable {
        let state = BinaryEncodingState(config: config)
        try state.encode(value, codingPath: [])
        return state.data
    }
}
