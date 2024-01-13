import Foundation

/// An encoder that encodes Swift structures to a flat Ocp1 representation.
public struct Ocp1Encoder {
    public init() {}

    /// Encodes a value to a flat Ocp1 representation.
    public func encode<Value>(_ value: Value) throws -> Data where Value: Encodable {
        let state = Ocp1EncodingState()
        try state.encode(value, codingPath: [])
        return state.data
    }
}
