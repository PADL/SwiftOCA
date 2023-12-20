/// An error that occurred during binary encoding.
public enum BinaryEncodingError: Error, Hashable {
    case nilNotEncodable
    case stringNotEncodable(String)
    case unsupportedType(String)
    case variableSizedTypeDisallowed
    case recursiveTypeDisallowed
    case optionalTypeDisallowed
    case valueAfterVariableSizedTypeDisallowed
    case variableSizedTypeTooBig
}
