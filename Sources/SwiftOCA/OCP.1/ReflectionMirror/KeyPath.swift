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
//
// MIT License
//
// Portions Copyright (c) 2022 Philip Turner
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

@_implementationOnly
import SwiftShims

// MARK: Implementation details

internal enum KeyPathComponentKind {
    /// The keypath references an externally-defined property or subscript whose
    /// component describes how to interact with the key path.
    case external
    /// The keypath projects within the storage of the outer value, like a
    /// stored property in a struct.
    case `struct`
    /// The keypath projects from the referenced pointer, like a
    /// stored property in a class.
    case `class`
    /// The keypath projects using a getter/setter pair.
    case computed
    /// The keypath optional-chains, returning nil immediately if the input is
    /// nil, or else proceeding by projecting the value inside.
    case optionalChain
    /// The keypath optional-forces, trapping if the input is
    /// nil, or else proceeding by projecting the value inside.
    case optionalForce
    /// The keypath wraps a value in an optional.
    case optionalWrap
}

internal struct RawKeyPathComponent {
    internal var header: Header
    internal var body: UnsafeRawBufferPointer

    internal init(header: Header, body: UnsafeRawBufferPointer) {
        self.header = header
        self.body = body
    }

    internal struct Header {
        internal var _value: UInt32

        init(discriminator: UInt32, payload: UInt32) {
            _value = 0
            self.discriminator = discriminator
            self.payload = payload
        }

        internal var discriminator: UInt32 {
            get {
                (_value & Header.discriminatorMask) >> Header.discriminatorShift
            }
            set {
                let shifted = newValue << Header.discriminatorShift
                precondition(
                    shifted & Header.discriminatorMask == shifted,
                    "discriminator doesn't fit"
                )
                _value = _value & ~Header.discriminatorMask | shifted
            }
        }

        internal var storedOffsetPayload: UInt32 {
            get {
                precondition(
                    kind == .struct || kind == .class,
                    "not a stored component"
                )
                return _value & Header.storedOffsetPayloadMask
            }
            set {
                precondition(
                    kind == .struct || kind == .class,
                    "not a stored component"
                )
                precondition(
                    newValue & Header.storedOffsetPayloadMask == newValue,
                    "payload too big"
                )
                _value = _value & ~Header.storedOffsetPayloadMask | newValue
            }
        }

        internal var payload: UInt32 {
            get {
                _value & Header.payloadMask
            }
            set {
                precondition(
                    newValue & Header.payloadMask == newValue,
                    "payload too big"
                )
                _value = _value & ~Header.payloadMask | newValue
            }
        }

        internal var endOfReferencePrefix: Bool {
            get {
                _value & Header.endOfReferencePrefixFlag != 0
            }
            set {
                if newValue {
                    _value |= Header.endOfReferencePrefixFlag
                } else {
                    _value &= ~Header.endOfReferencePrefixFlag
                }
            }
        }

        internal var kind: KeyPathComponentKind {
            switch (discriminator, payload) {
            case (Header.externalTag, _):
                return .external
            case (Header.structTag, _):
                return .struct
            case (Header.classTag, _):
                return .class
            case (Header.computedTag, _):
                return .computed
            case (Header.optionalTag, Header.optionalChainPayload):
                return .optionalChain
            case (Header.optionalTag, Header.optionalWrapPayload):
                return .optionalWrap
            case (Header.optionalTag, Header.optionalForcePayload):
                return .optionalForce
            default:
                fatalError("invalid header")
            }
        }

        internal static var payloadMask: UInt32 {
            _SwiftKeyPathComponentHeader_PayloadMask
        }

        internal static var discriminatorMask: UInt32 {
            _SwiftKeyPathComponentHeader_DiscriminatorMask
        }

        internal static var discriminatorShift: UInt32 {
            _SwiftKeyPathComponentHeader_DiscriminatorShift
        }

        internal static var externalTag: UInt32 {
            _SwiftKeyPathComponentHeader_ExternalTag
        }

        internal static var structTag: UInt32 {
            _SwiftKeyPathComponentHeader_StructTag
        }

        internal static var computedTag: UInt32 {
            _SwiftKeyPathComponentHeader_ComputedTag
        }

        internal static var classTag: UInt32 {
            _SwiftKeyPathComponentHeader_ClassTag
        }

        internal static var optionalTag: UInt32 {
            _SwiftKeyPathComponentHeader_OptionalTag
        }

        internal static var optionalChainPayload: UInt32 {
            _SwiftKeyPathComponentHeader_OptionalChainPayload
        }

        internal static var optionalWrapPayload: UInt32 {
            _SwiftKeyPathComponentHeader_OptionalWrapPayload
        }

        internal static var optionalForcePayload: UInt32 {
            _SwiftKeyPathComponentHeader_OptionalForcePayload
        }

        internal static var endOfReferencePrefixFlag: UInt32 {
            _SwiftKeyPathComponentHeader_EndOfReferencePrefixFlag
        }

        internal static var storedMutableFlag: UInt32 {
            _SwiftKeyPathComponentHeader_StoredMutableFlag
        }

        internal static var storedOffsetPayloadMask: UInt32 {
            _SwiftKeyPathComponentHeader_StoredOffsetPayloadMask
        }

        internal static var outOfLineOffsetPayload: UInt32 {
            _SwiftKeyPathComponentHeader_OutOfLineOffsetPayload
        }

        internal static var unresolvedFieldOffsetPayload: UInt32 {
            _SwiftKeyPathComponentHeader_UnresolvedFieldOffsetPayload
        }

        internal static var unresolvedIndirectOffsetPayload: UInt32 {
            _SwiftKeyPathComponentHeader_UnresolvedIndirectOffsetPayload
        }

        internal static var maximumOffsetPayload: UInt32 {
            _SwiftKeyPathComponentHeader_MaximumOffsetPayload
        }

        // The component header is 4 bytes, but may be followed by an aligned
        // pointer field for some kinds of component, forcing padding.
        internal static var pointerAlignmentSkew: Int {
            MemoryLayout<Int>.size - MemoryLayout<Int32>.size
        }

        init(
            stored kind: KeyPathStructOrClass,
            mutable: Bool,
            inlineOffset: UInt32
        ) {
            let discriminator: UInt32
            switch kind {
            case .struct: discriminator = Header.structTag
            case .class: discriminator = Header.classTag
            }

            precondition(inlineOffset <= Header.maximumOffsetPayload)
            let payload = inlineOffset
                | (mutable ? Header.storedMutableFlag : 0)
            self.init(
                discriminator: discriminator,
                payload: payload
            )
        }
    }

    internal func clone(
        into buffer: inout UnsafeMutableRawBufferPointer,
        endOfReferencePrefix: Bool
    ) {
        var newHeader = header
        newHeader.endOfReferencePrefix = endOfReferencePrefix

        var componentSize = MemoryLayout<Header>.size
        buffer.storeBytes(of: newHeader, as: Header.self)
        switch header.kind {
        case .struct,
             .class:
            if header.storedOffsetPayload == Header.outOfLineOffsetPayload {
                let overflowOffset = body.load(as: UInt32.self)
                buffer.storeBytes(
                    of: overflowOffset,
                    toByteOffset: 4,
                    as: UInt32.self
                )
                componentSize += 4
            }
        case .optionalChain,
             .optionalForce,
             .optionalWrap:
            break
        case .computed:
            // Metadata does not have enough information to construct computed
            // properties. In the Swift stdlib, this case would trigger a large block
            // of code. That code is left out because it is not necessary.
            fatalError("Implement support for key paths to computed properties.")
        case .external:
            fatalError("should have been instantiated away")
        }
        buffer = UnsafeMutableRawBufferPointer(
            start: buffer.baseAddress.unsafelyUnwrapped + componentSize,
            count: buffer.count - componentSize
        )
    }
}

internal enum KeyPathBuffer {
    internal struct Builder {
        internal var buffer: UnsafeMutableRawBufferPointer
        internal init(_ buffer: UnsafeMutableRawBufferPointer) {
            self.buffer = buffer
        }

        internal mutating func pushRaw(
            size: Int, alignment: Int
        ) -> UnsafeMutableRawBufferPointer {
            var baseAddress = buffer.baseAddress.unsafelyUnwrapped
            var misalign = Int(bitPattern: baseAddress) & (alignment - 1)
            if misalign != 0 {
                misalign = alignment - misalign
                baseAddress = baseAddress.advanced(by: misalign)
            }
            let result = UnsafeMutableRawBufferPointer(
                start: baseAddress,
                count: size
            )
            buffer = UnsafeMutableRawBufferPointer(
                start: baseAddress + size,
                count: buffer.count - size - misalign
            )
            return result
        }

        internal mutating func push<T>(_ value: T) {
            let buf = pushRaw(
                size: MemoryLayout<T>.size,
                alignment: MemoryLayout<T>.alignment
            )
            buf.storeBytes(of: value, as: T.self)
        }

        internal mutating func pushHeader(_ header: Header) {
            push(header)
            // Start the components at pointer alignment
            _ = pushRaw(
                size: RawKeyPathComponent.Header.pointerAlignmentSkew,
                alignment: 4
            )
        }
    }

    internal struct Header {
        internal var _value: UInt32
        internal init(size: Int, trivial: Bool, hasReferencePrefix: Bool) {
            precondition(
                size <= Int(Header.sizeMask),
                "key path too big"
            )
            _value = UInt32(size)
                | (trivial ? Header.trivialFlag : 0)
                | (hasReferencePrefix ? Header.hasReferencePrefixFlag : 0)
        }

        internal static var sizeMask: UInt32 {
            _SwiftKeyPathBufferHeader_SizeMask
        }

        internal static var reservedMask: UInt32 {
            _SwiftKeyPathBufferHeader_ReservedMask
        }

        internal static var trivialFlag: UInt32 {
            _SwiftKeyPathBufferHeader_TrivialFlag
        }

        internal static var hasReferencePrefixFlag: UInt32 {
            _SwiftKeyPathBufferHeader_HasReferencePrefixFlag
        }
    }
}

internal enum KeyPathStructOrClass {
    case `struct`, `class`
}
