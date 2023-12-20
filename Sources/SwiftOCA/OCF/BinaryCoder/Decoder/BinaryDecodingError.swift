import Foundation

/// An error that occurred during binary encoding.
public enum BinaryDecodingError: Error, Hashable {
    case eofTooEarly
    case stringNotDecodable(Data)
}
