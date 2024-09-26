//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#if swift(>=6.0)
internal import KeyPathShims
internal import SwiftShims
#else
@_implementationOnly import KeyPathShims
@_implementationOnly import SwiftShims
#endif

@_silgen_name("swift_isClassType")
func _isClassType(_: Any.Type) -> Bool

@_silgen_name("swift_getMetadataKind")
func _metadataKind(_: Any.Type) -> UInt

@_silgen_name("swift_reflectionMirror_recursiveCount")
func _getRecursiveChildCount(_: Any.Type) -> Int

@_silgen_name("swift_reflectionMirror_recursiveChildMetadata")
func _getChildMetadata(
  _: Any.Type,
  index: Int,
  fieldMetadata: UnsafeMutablePointer<_FieldReflectionMetadata>
) -> Any.Type

@_silgen_name("swift_reflectionMirror_recursiveChildOffset")
func _getChildOffset(
  _: Any.Type,
  index: Int
) -> Int

@_silgen_name("swift_getDynamicType")
func _getDynamicType(
  _: Any,
  self: Any.Type,
  existentialMetatype: Bool
) -> Any.Type?

/// Options for calling `_forEachField(of:options:body:)`.
struct _EachFieldOptions: OptionSet {
  public var rawValue: UInt32

  public init(rawValue: UInt32) {
    self.rawValue = rawValue
  }

  /// Require the top-level type to be a class.
  ///
  /// If this is not set, the top-level type is required to be a struct or
  /// tuple.
  public static let classType = _EachFieldOptions(rawValue: 1 << 0)

  /// Ignore fields that can't be introspected.
  ///
  /// If not set, the presence of things that can't be introspected causes
  /// the function to immediately return `false`.
  public static let ignoreUnknown = _EachFieldOptions(rawValue: 1 << 1)
}

/// The metadata "kind" for a type.
enum _MetadataKind: UInt {
  // With "flags":
  // runtimePrivate = 0x100
  // nonHeap = 0x200
  // nonType = 0x400

  case `class` = 0
  case `struct` = 0x200 // 0 | nonHeap
  case `enum` = 0x201 // 1 | nonHeap
  case optional = 0x202 // 2 | nonHeap
  case foreignClass = 0x203 // 3 | nonHeap
  case opaque = 0x300 // 0 | runtimePrivate | nonHeap
  case tuple = 0x301 // 1 | runtimePrivate | nonHeap
  case function = 0x302 // 2 | runtimePrivate | nonHeap
  case existential = 0x303 // 3 | runtimePrivate | nonHeap
  case metatype = 0x304 // 4 | runtimePrivate | nonHeap
  case objcClassWrapper = 0x305 // 5 | runtimePrivate | nonHeap
  case existentialMetatype = 0x306 // 6 | runtimePrivate | nonHeap
  case heapLocalVariable = 0x400 // 0 | nonType
  case heapGenericLocalVariable = 0x500 // 0 | nonType | runtimePrivate
  case errorObject = 0x501 // 1 | nonType | runtimePrivate
  case unknown = 0xFFFF

  init(_ type: Any.Type) {
    let v = _metadataKind(type)
    if let result = _MetadataKind(rawValue: v) {
      self = result
    } else {
      self = .unknown
    }
  }
}

/// Calls the given closure on every field of the specified type.
///
/// If `body` returns `false` for any field, no additional fields are visited.
///
/// - Parameters:
///   - type: The type to inspect.
///   - options: Options to use when reflecting over `type`.
///   - body: A closure to call with information about each field in `type`.
///     The parameters to `body` are a pointer to a C string holding the name
///     of the field, the offset of the field in bytes, the type of the field,
///     and the `_MetadataKind` of the field's type.
/// - Returns: `true` if every invocation of `body` returns `true`; otherwise,
///   `false`.
@discardableResult
func _forEachField(
  of type: Any.Type,
  options: _EachFieldOptions = [],
  body: (UnsafePointer<CChar>, Int, Any.Type, _MetadataKind) -> Bool
) -> Bool {
  // Require class type iff `.classType` is included as an option
  if _isClassType(type) != options.contains(.classType) {
    return false
  }

  let childCount = _getRecursiveChildCount(type)
  for i in 0..<childCount {
    let offset = _getChildOffset(type, index: i)

    var field = _FieldReflectionMetadata()
    let childType = _getChildMetadata(type, index: i, fieldMetadata: &field)
    defer { field.freeFunc?(field.name) }
    let kind = _MetadataKind(childType)

    if !body(field.name!, offset, childType, kind) {
      return false
    }
  }

  return true
}

/// Calls the given closure on every field of the specified type.
///
/// If `body` returns `false` for any field, no additional fields are visited.
///
/// - Parameters:
///   - type: The type to inspect.
///   - options: Options to use when reflecting over `type`.
///   - body: A closure to call with information about each field in `type`.
///     The parameters to `body` are a pointer to a C string holding the name
///     of the field and an erased keypath for it.
/// - Returns: `true` if every invocation of `body` returns `true`; otherwise,
///   `false`.
@discardableResult
func _forEachFieldWithKeyPath<Root>(
  of type: Root.Type,
  options: _EachFieldOptions = [],
  body: (UnsafePointer<CChar>, PartialKeyPath<Root>) -> Bool
) -> Bool {
  // Require class type iff `.classType` is included as an option
  if _isClassType(type) != options.contains(.classType) {
    return false
  }

  let ignoreUnknown = options.contains(.ignoreUnknown)

  let childCount = _getRecursiveChildCount(type)
  for i in 0..<childCount {
    let offset = _getChildOffset(type, index: i)

    var field = _FieldReflectionMetadata()
    let childType = _getChildMetadata(type, index: i, fieldMetadata: &field)
    defer { field.freeFunc?(field.name) }
    let kind = _MetadataKind(childType)
    let supportedType = switch kind {
    case .struct, .class, .optional, .existential,
         .existentialMetatype, .tuple, .enum:
      true
    default:
      false
    }
    if !supportedType || !field.isStrong {
      if !ignoreUnknown { return false }
      continue
    }
    func keyPathType<Leaf>(for: Leaf.Type) -> PartialKeyPath<Root>.Type {
      if field.isVar { return WritableKeyPath<Root, Leaf>.self }
      return KeyPath<Root, Leaf>.self
    }
    let resultSize = MemoryLayout<Int32>.size + MemoryLayout<Int>.size
    let partialKeyPathExistential = _openExistential(childType, do: keyPathType)
    let partialKeyPath = partialKeyPathExistential
      ._create(capacityInBytes: resultSize) {
        var destBuilder = KeyPathBuffer.Builder($0)
        destBuilder.pushHeader(KeyPathBuffer.Header(
          size: resultSize - MemoryLayout<Int>.size,
          trivial: true,
          hasReferencePrefix: false
        ))
        let componentHeader = RawKeyPathComponent.Header(
          stored: _MetadataKind(type) == .struct ? .struct : .class,
          mutable: field.isVar,
          inlineOffset: UInt32(offset)
        )
        let component = RawKeyPathComponent(
          header: componentHeader,
          body: UnsafeRawBufferPointer(start: nil, count: 0)
        )
        component.clone(
          into: &destBuilder.buffer,
          endOfReferencePrefix: false
        )
      }

    if !body(field.name!, partialKeyPath) {
      return false
    }
  }
  return true
}

@discardableResult
func _forEachFieldWithKeyPath<T>(
  value: T,
  options: _EachFieldOptions = [],
  body: (UnsafePointer<CChar>, PartialKeyPath<T>) -> Bool
) -> Bool {
  _forEachFieldWithKeyPath(
    of: _getDynamicType(
      value,
      self: T.self,
      existentialMetatype: false
    ) as! T.Type,
    options: options,
    body: body
  )
}

public func _allKeyPaths<T>(value: T) -> [String: PartialKeyPath<T>] {
  var keyPaths = [String: PartialKeyPath<T>]()
  _forEachFieldWithKeyPath(value: value, options: [.classType, .ignoreUnknown]) { field, path in
    let fieldName = String(cString: field)
    keyPaths[fieldName] = path
    return true
  }
  return keyPaths
}
