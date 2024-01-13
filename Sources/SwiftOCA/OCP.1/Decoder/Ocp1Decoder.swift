import Foundation

protocol ArrayRepresentable {}
extension Array: ArrayRepresentable {}

/// A decoder that decodes Swift structures from a flat Ocp1 representation.
public struct Ocp1Decoder {
    public init() {}

    /// Decodes a value from a flat Ocp1 representation.
    public func decode<Value>(_ type: Value.Type, from data: Data) throws -> Value
        where Value: Decodable
    {
        let state = Ocp1DecodingState(data: data)
        var count: Int? = nil
        if type is any ArrayRepresentable.Type {
            // propagate array count to unkeyed container count
            count = try Int(UInt16(from: Ocp1DecoderImpl(state: state, codingPath: [])))
        }
        return try Value(from: Ocp1DecoderImpl(state: state, codingPath: [], count: count))
    }
}
