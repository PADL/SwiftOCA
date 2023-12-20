/// The byte order of a fixed-width integer.
public enum Endianness {
    case platformDefault
    case bigEndian
    case littleEndian

    /// Converts to the endianness.
    func apply<Integer>(_ value: Integer) -> Integer where Integer: FixedWidthInteger {
        switch self {
        case .platformDefault: return value
        case .bigEndian: return value.bigEndian
        case .littleEndian: return value.littleEndian
        }
    }

    /// Converts from the endianness to the platform's default endianness.
    func assume<Integer>(_ value: Integer) -> Integer where Integer: FixedWidthInteger {
        switch self {
        case .platformDefault: return value
        case .bigEndian: return .init(bigEndian: value)
        case .littleEndian: return .init(littleEndian: value)
        }
    }
}
