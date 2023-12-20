import Foundation

protocol ArrayRepresentable {}
extension Array: ArrayRepresentable {}

/// A decoder that decodes Swift structures from a flat binary representation.
public struct BinaryDecoder {
    private let config: BinaryCodingConfiguration

    public init(config: BinaryCodingConfiguration = .init()) {
        self.config = config
    }

    /// Decodes a value from a flat binary representation.
    public func decode<Value>(_ type: Value.Type, from data: Data) throws -> Value where Value: Decodable {
        let state = BinaryDecodingState(config: config, data: data)
        var count: Int? = nil
        if type is any ArrayRepresentable.Type, config.variableSizedTypeStrategy == .lengthTaggedArrays {
            // propagate array count to unkeyed container count
            count = try Int(UInt16(from: BinaryDecoderImpl(state: state, codingPath: [])))
        }
        return try Value(from: BinaryDecoderImpl(state: state, codingPath: [], count: count))
    }
}
