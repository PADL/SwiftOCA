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

/// A decoder that decodes Swift structures from a flat Ocp1 representation.
public struct Ocp1Decoder {
    public var userInfo: [CodingUserInfoKey: Any] = [:]

    public init() {}

    /// Decodes a value from a flat Ocp1 representation.
    public func decode<Value>(_ type: Value.Type, from data: [UInt8]) throws -> Value
        where Value: Decodable
    {
        try decode(type, from: Data(data))
    }

    /// Decodes a value from a flat Ocp1 representation.
    public func decode<Value>(_ type: Value.Type, from data: Data) throws -> Value
        where Value: Decodable
    {
        let state: Ocp1DecodingState
        state = Ocp1DecodingState(data: Data(data), userInfo: userInfo)
        return try ocp1Decode(type, state: state, codingPath: [], userInfo: userInfo)
    }
}
