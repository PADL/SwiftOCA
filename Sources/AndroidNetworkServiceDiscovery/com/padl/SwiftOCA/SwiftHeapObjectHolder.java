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

package com.padl.SwiftOCA;

import java.lang.ref.Cleaner;

/// Holds a strong reference to a Swift heap object on behalf of a Java object.
///
/// swift-java cannot implement a Java interface directly from Swift, so each
/// listener interface we need is implemented by a small Java class extending
/// this holder and declaring its interface methods `native`. The Swift side
/// then supplies the bodies via `@JavaImplementation`, recovering the Swift
/// object from `_swiftHeapObject`.
///
/// This mirrors FlutterSwift's holder of the same name; the two are deliberately
/// independent so that SwiftOCA does not depend on FlutterSwift.
public class SwiftHeapObjectHolder implements AutoCloseable {
  private static final Cleaner cleaner = Cleaner.create();

  private final Cleaner.Cleanable _cleanable;
  public long _swiftHeapObject;

  public SwiftHeapObjectHolder(long heapObjectInt64Ptr) {
    final Runnable F = () -> SwiftHeapObjectHolder._releaseSwiftHeapObject(heapObjectInt64Ptr);
    SwiftHeapObjectHolder._retainSwiftHeapObject(heapObjectInt64Ptr);
    _cleanable = cleaner.register(this, F);
    _swiftHeapObject = heapObjectInt64Ptr;
  }

  @Override
  public void close() throws Exception {
    _swiftHeapObject = 0;
    _cleanable.clean();
  }

  static native void _retainSwiftHeapObject(long heapObjectInt64Ptr);
  static native void _releaseSwiftHeapObject(long heapObjectInt64Ptr);
}
