//
// Copyright (c) 2022 fwcd
// Portions (c) 2023-2024 PADL Software Pty Ltd
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
//

import Foundation

/// The internal state used by the decoders.
class Ocp1DecodingState {
    private var data: Data
    let userInfo: [CodingUserInfoKey: Any]
    var isAtEnd: Bool { data.isEmpty }

    init(data: Data, userInfo: [CodingUserInfoKey: Any]) {
        self.data = data
        self.userInfo = userInfo
    }

    func decodeNil() throws -> Bool {
        // Since we don't encode `nil`s, we just always return `false``
        false
    }

    func decode(_ type: Bool.Type) throws -> Bool {
        guard let byte = data.popFirst() else {
            throw Ocp1Error.pduTooShort
        }
        return byte != 0
    }

    // https://forums.swift.org/t/decoding-utf8-tagged-with-number-of-code-points/69427

    func decode(_ type: String.Type) throws -> String {
        let scalarCount = try Int(decodeInteger(UInt16.self))

        // Count the number of valid UTF-8 code units.
        var utf8Count = 0
        var iterator = data.makeIterator()
        var utf8Parser = Unicode.UTF8.ForwardParser()
        for _ in 0..<scalarCount {
            switch utf8Parser.parseScalar(from: &iterator) {
            case let .valid(utf8Buffer):
                utf8Count += utf8Buffer.count
            case .emptyInput:
                throw Ocp1Error.pduTooShort
            case .error:
                throw Ocp1Error.stringNotDecodable([UInt8](data))
            }
        }

        // Decode and remove the code units.
        let utf8Prefix = data.prefix(utf8Count)
        data.removeFirst(utf8Count)
        return String(unsafeUninitializedCapacity: utf8Count) {
            _ = $0.initialize(fromContentsOf: utf8Prefix)
            return utf8Count
        }
    }

    func decodeInteger<Integer>(_ type: Integer.Type) throws -> Integer
        where Integer: FixedWidthInteger
    {
        let byteWidth = Integer.bitWidth / 8

        guard data.count >= byteWidth else {
            throw Ocp1Error.pduTooShort
        }

        let value = data.prefix(byteWidth).withUnsafeBytes {
            Integer(bigEndian: $0.loadUnaligned(as: Integer.self))
        }

        data.removeFirst(byteWidth)
        return value
    }

    func decode(_ type: Double.Type) throws -> Double {
        Double(bitPattern: try decodeInteger(UInt64.self))
    }

    func decode(_ type: Float.Type) throws -> Float {
        Float(bitPattern: try decodeInteger(UInt32.self))
    }

    func decode(_ type: Int.Type) throws -> Int {
        try decodeInteger(type)
    }

    func decode(_ type: Int8.Type) throws -> Int8 {
        try decodeInteger(type)
    }

    func decode(_ type: Int16.Type) throws -> Int16 {
        try decodeInteger(type)
    }

    func decode(_ type: Int32.Type) throws -> Int32 {
        try decodeInteger(type)
    }

    func decode(_ type: Int64.Type) throws -> Int64 {
        try decodeInteger(type)
    }

    func decode(_ type: UInt.Type) throws -> UInt {
        try decodeInteger(type)
    }

    func decode(_ type: UInt8.Type) throws -> UInt8 {
        try decodeInteger(type)
    }

    func decode(_ type: UInt16.Type) throws -> UInt16 {
        try decodeInteger(type)
    }

    func decode(_ type: UInt32.Type) throws -> UInt32 {
        try decodeInteger(type)
    }

    func decode(_ type: UInt64.Type) throws -> UInt64 {
        try decodeInteger(type)
    }

    func decodeCount<T: Collection & Decodable>(_ type: T.Type) throws -> Int {
        let count: Int

        if type is any Ocp1LongList.Type {
            // FIXME: can't support 2^32 length because on 32-bit platforms count is Int32
            count =
                try Int(Int32(from: Ocp1DecoderImpl(
                    state: self,
                    codingPath: [],
                    userInfo: userInfo
                )))
        } else {
            count =
                try Int(UInt16(from: Ocp1DecoderImpl(
                    state: self,
                    codingPath: [],
                    userInfo: userInfo
                )))
        }

        return count
    }

    func decode<T>(_ type: T.Type, codingPath: [any CodingKey]) throws -> T where T: Decodable {
        try Ocp1DecodingState.decode(type, state: self, codingPath: [], userInfo: userInfo)
    }

    static func decode<T>(
        _ type: T.Type,
        state: Ocp1DecodingState,
        codingPath: [any CodingKey],
        userInfo: [CodingUserInfoKey: Any]
    ) throws -> T where T: Decodable {
        let count: Int?
        if let type = type as? any Ocp1MapRepresentable.Type {
            count = try state.decodeCount(type)
            let decoder = Ocp1DecoderImpl(
                state: state,
                codingPath: [],
                userInfo: userInfo,
                count: count
            )
            return try type.init(from: decoder) as! T
        } else {
            if let type = type as? any Ocp1ListRepresentable.Type {
                count = try state.decodeCount(type)
            } else {
                count = nil
            }
            return try T(from: Ocp1DecoderImpl(
                state: state,
                codingPath: [],
                userInfo: userInfo,
                count: count
            ))
        }
    }
}
