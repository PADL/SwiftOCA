//
// Copyright (c) 2026 PADL Software Pty Ltd
//
// Licensed under the Apache License, Version 2.0 (the License);
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an 'AS IS' BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#if canImport(Darwin)
// Apple's SDKs leave the standard library's SPI out of the interface Xcode imports, so
// bind its public, ABI-stable symbol. The options and the field's metadata kind are
// resilient types, passed by address.
@_silgen_name("$ss13_forEachField2of7options4bodySbypXp_s01_bC7OptionsVSbSPys4Int8VG_SiypXps13_MetadataKindOtXEtF")
@discardableResult
private func _stdlibForEachField(
  of type: Any.Type,
  options: UnsafePointer<UInt32>,
  body: (UnsafePointer<CChar>, Int, Any.Type, UnsafeRawPointer) -> Bool
) -> Bool
#else
@_spi(Reflection) import Swift
#endif

/// Calls `body` with the name and type of each stored property of the struct `type`, in
/// declaration order, until it returns false. This is the standard library's own field
/// walk, which `Mirror` is built on.
@discardableResult
package func _ocaForEachField(
  of type: Any.Type,
  body: (UnsafePointer<CChar>, Any.Type) -> Bool
) -> Bool {
  #if canImport(Darwin)
  var options: UInt32 = 0
  return _stdlibForEachField(of: type, options: &options) { name, _, fieldType, _ in
    body(name, fieldType)
  }
  #else
  return _forEachField(of: type) { name, _, fieldType, _ in body(name, fieldType) }
  #endif
}
