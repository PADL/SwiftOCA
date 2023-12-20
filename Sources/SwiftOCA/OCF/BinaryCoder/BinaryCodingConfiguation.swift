import Foundation

/// A configuration for the binary encoder/decoder.
public struct BinaryCodingConfiguration {
    /// The endianness to use for fixed-width integers.
    let endianness: Endianness
    /// The encoding to use for strings.
    let stringEncoding: String.Encoding
    /// Whether to add a NUL byte to encoded strings. This makes them exempt
    /// from the variable length rules since they are properly delimited.
    let stringTypeStrategy: StringTypeStrategy
    /// The strategy used for variable-sized types.
    let variableSizedTypeStrategy: VariableSizedTypeStrategy

    public init(
        endianness: Endianness = .bigEndian,
        stringEncoding: String.Encoding = .utf8,
        nullTerminateStrings: Bool = true,
        variableSizedTypeStrategy: VariableSizedTypeStrategy = .untagged
    ) {
        self.init(endianness: endianness,
                  stringEncoding: stringEncoding,
                  stringTypeStrategy: nullTerminateStrings ? .nullTerminate : .none,
                  variableSizedTypeStrategy: variableSizedTypeStrategy)
    }
    
    public init(
        endianness: Endianness,
        stringEncoding: String.Encoding,
        stringTypeStrategy: StringTypeStrategy,
        variableSizedTypeStrategy: VariableSizedTypeStrategy
    ) {
        self.endianness = endianness
        self.stringEncoding = stringEncoding
        self.stringTypeStrategy = stringTypeStrategy
        self.variableSizedTypeStrategy = variableSizedTypeStrategy
    }
}
