//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Swift
@_implementationOnly
import SwiftShims

class AnyKeyPath {
    /// Used to store the offset from the root to the value
    /// in the case of a pure struct KeyPath.
    /// It's a regular kvcKeyPathStringPtr otherwise.
    final var _kvcKeyPathStringPtr: UnsafePointer<CChar>?
}

public extension Swift.AnyKeyPath {
    @_spi(SwiftOCAPrivate)
    static func _create(
        capacityInBytes bytes: Int,
        initializedBy body: (UnsafeMutableRawBufferPointer) -> ()
    ) -> Self {
        precondition(
            bytes > 0 && bytes % 4 == 0,
            "capacity must be multiple of 4 bytes"
        )
        let result = Builtin.allocWithTailElems_1(
            self,
            (bytes / 4)._builtinWordValue,
            Int32.self
        )
        unsafeBitCast(result, to: AnyKeyPath.self)._kvcKeyPathStringPtr = nil
        let tailAllocOffset = 3 * MemoryLayout<Int>.stride
        let base = unsafeBitCast(result, to: UnsafeMutableRawPointer.self)
            .advanced(by: tailAllocOffset)
        body(UnsafeMutableRawBufferPointer(start: base, count: bytes))
        return result
    }
}
