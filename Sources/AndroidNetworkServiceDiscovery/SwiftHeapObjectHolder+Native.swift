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

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SwiftJava

public extension SwiftHeapObjectHolder {
  fileprivate static func _getUnmanagedSwiftHeapObject(_ heapObjectInt64Ptr: Int64)
    -> Unmanaged<AnyObject>?
  {
    guard heapObjectInt64Ptr != 0 else { return nil }
    return unsafeBitCast(Int(heapObjectInt64Ptr), to: Unmanaged<AnyObject>.self)
  }

  convenience init(swiftObject: some AnyObject, environment: JNIEnvironment? = nil) {
    let heapObjectPtr = Unmanaged.passUnretained(swiftObject).toOpaque()
    let heapObjectInt64 = Int64(Int(bitPattern: heapObjectPtr))
    self.init(heapObjectInt64, environment: environment) // will call retain()
  }

  var swiftObject: AnyObject? {
    SwiftHeapObjectHolder._getUnmanagedSwiftHeapObject(_swiftHeapObject)?.takeUnretainedValue()
  }
}

// Android's JNI cannot find application classes from threads it did not create,
// so the class loader is captured once and handed back here.
//
// Unlike FlutterSwift, this cannot be done from `JNI_OnLoad`: only one
// definition of that symbol may exist per shared library, and when SwiftOCA is
// linked into a Flutter app, FlutterAndroid already owns it. It is captured in
// `AndroidNsd.configure(context:)` instead, which is necessarily called from
// a Java-originated thread where the lookup succeeds.
extension SwiftHeapObjectHolder: AnyJavaObjectWithCustomClassLoader {
  public static func getJavaClassLoader(in environment: JNIEnvironment) throws -> JavaClassLoader! {
    AndroidNsd._classLoader
  }
}

// Use @_cdecl directly rather than @JavaImplementation on JavaClass<T>, since
// swift-java's @JavaImplementation macro produces malformed expansions for
// generic class specializations (swiftlang/swift-java#674 regression).
//
// The `clazz` parameter must be the C `jobject` type from <jni.h>, not JavaKit's
// `JavaObject` Swift class -- @_cdecl requires every parameter to be
// representable in Objective-C, and Swift class types are not.
@_cdecl("Java_com_padl_SwiftOCA_SwiftHeapObjectHolder__1retainSwiftHeapObject")
public func Java_com_padl_SwiftOCA_SwiftHeapObjectHolder__1retainSwiftHeapObject(
  _ environment: JNIEnvironment?,
  _ clazz: jobject?,
  _ heapObjectInt64Ptr: Int64
) {
  _ = SwiftHeapObjectHolder._getUnmanagedSwiftHeapObject(heapObjectInt64Ptr)?.retain()
}

@_cdecl("Java_com_padl_SwiftOCA_SwiftHeapObjectHolder__1releaseSwiftHeapObject")
public func Java_com_padl_SwiftOCA_SwiftHeapObjectHolder__1releaseSwiftHeapObject(
  _ environment: JNIEnvironment?,
  _ clazz: jobject?,
  _ heapObjectInt64Ptr: Int64
) {
  SwiftHeapObjectHolder._getUnmanagedSwiftHeapObject(heapObjectInt64Ptr)?.release()
}
