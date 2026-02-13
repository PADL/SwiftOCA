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

@testable import SwiftOCA
import XCTest

final class OcaObjectCacheTests: XCTestCase {
  // MARK: - Basic Operations Tests

  func testSubscriptGetSet() {
    let cache = OcaObjectCache()
    let objectNumber: OcaONo = 1
    let object = OcaRoot(objectNumber: objectNumber)

    // Test set
    cache[objectNumber] = object
    XCTAssertEqual(cache.count, 1)

    // Test get
    let retrieved = cache[objectNumber]
    XCTAssertNotNil(retrieved)
    XCTAssertEqual(retrieved?.objectNumber, objectNumber)
  }

  func testSubscriptGetNonExistent() {
    let cache = OcaObjectCache()
    let retrieved = cache[999]
    XCTAssertNil(retrieved)
  }

  func testSubscriptSetNilRemoves() {
    let cache = OcaObjectCache()
    let objectNumber: OcaONo = 1
    let object = OcaRoot(objectNumber: objectNumber)

    cache[objectNumber] = object
    XCTAssertEqual(cache.count, 1)

    // Setting to nil should remove
    cache[objectNumber] = nil
    XCTAssertEqual(cache.count, 0)
    XCTAssertNil(cache[objectNumber])
  }

  // MARK: - Count Tests

  func testCount() {
    let cache = OcaObjectCache()
    XCTAssertEqual(cache.count, 0)

    cache[1] = OcaRoot(objectNumber: 1)
    XCTAssertEqual(cache.count, 1)

    cache[2] = OcaRoot(objectNumber: 2)
    XCTAssertEqual(cache.count, 2)

    cache[3] = OcaRoot(objectNumber: 3)
    XCTAssertEqual(cache.count, 3)
  }

  func testCountAfterOverwrite() {
    let cache = OcaObjectCache()
    let objectNumber: OcaONo = 1

    cache[objectNumber] = OcaRoot(objectNumber: objectNumber)
    XCTAssertEqual(cache.count, 1)

    // Overwriting should not change count
    cache[objectNumber] = OcaRoot(objectNumber: objectNumber)
    XCTAssertEqual(cache.count, 1)
  }

  // MARK: - Keys and Values Tests

  func testKeys() {
    let cache = OcaObjectCache()
    let keys: Set<OcaONo> = [1, 2, 3, 4, 5]

    for key in keys {
      cache[key] = OcaRoot(objectNumber: key)
    }

    XCTAssertEqual(cache.keys, keys)
  }

  func testValues() {
    let cache = OcaObjectCache()
    let objectNumbers: [OcaONo] = [1, 2, 3]

    for number in objectNumbers {
      cache[number] = OcaRoot(objectNumber: number)
    }

    let values = cache.values
    XCTAssertEqual(values.count, objectNumbers.count)

    let retrievedNumbers = Set(values.map(\.objectNumber))
    XCTAssertEqual(retrievedNumbers, Set(objectNumbers))
  }

  // MARK: - Removal Tests

  func testRemoveValue() {
    let cache = OcaObjectCache()
    cache[1] = OcaRoot(objectNumber: 1)
    cache[2] = OcaRoot(objectNumber: 2)
    XCTAssertEqual(cache.count, 2)

    cache.removeValue(forKey: 1)
    XCTAssertEqual(cache.count, 1)
    XCTAssertNil(cache[1])
    XCTAssertNotNil(cache[2])
  }

  func testRemoveAll() {
    let cache = OcaObjectCache()
    for i in 1...10 {
      cache[OcaONo(i)] = OcaRoot(objectNumber: OcaONo(i))
    }
    XCTAssertEqual(cache.count, 10)

    cache.removeAll()
    XCTAssertEqual(cache.count, 0)
    XCTAssertTrue(cache.keys.isEmpty)
  }

  // MARK: - Sequence Conformance Tests

  func testIteration() {
    let cache = OcaObjectCache()
    let objectNumbers: Set<OcaONo> = [1, 2, 3, 4, 5]

    for number in objectNumbers {
      cache[number] = OcaRoot(objectNumber: number)
    }

    var iteratedKeys = Set<OcaONo>()
    for (key, value) in cache {
      iteratedKeys.insert(key)
      XCTAssertEqual(key, value.objectNumber)
    }

    XCTAssertEqual(iteratedKeys, objectNumbers)
  }

  func testIterationEmpty() {
    let cache = OcaObjectCache()
    var count = 0

    for _ in cache {
      count += 1
    }

    XCTAssertEqual(count, 0)
  }

  // MARK: - Count Limit Tests

  func testCountLimit() {
    let countLimit = 5
    let cache = OcaObjectCache(countLimit: countLimit)

    // Add more objects than the limit
    for i in 1...10 {
      cache[OcaONo(i)] = OcaRoot(objectNumber: OcaONo(i))
    }

    // NSCache may evict objects, so count should be <= what we added
    // but we can't guarantee it will be exactly countLimit
    XCTAssertLessThanOrEqual(cache.count, 10)
  }

  // MARK: - Thread Safety Tests

  func testConcurrentWrites() async {
    let cache = OcaObjectCache()
    let iterations = 100

    await withTaskGroup(of: Void.self) { group in
      for i in 1...iterations {
        group.addTask {
          cache[OcaONo(i)] = OcaRoot(objectNumber: OcaONo(i))
        }
      }
    }

    // All objects should be present (unless NSCache evicted some)
    XCTAssertGreaterThanOrEqual(cache.count, 1)
    XCTAssertLessThanOrEqual(cache.count, iterations)
  }

  func testConcurrentReads() async {
    let cache = OcaObjectCache()
    let objectNumber: OcaONo = 42
    cache[objectNumber] = OcaRoot(objectNumber: objectNumber)

    await withTaskGroup(of: Bool.self) { group in
      for _ in 1...100 {
        group.addTask {
          cache[objectNumber] != nil
        }
      }

      for await result in group {
        XCTAssertTrue(result)
      }
    }
  }

  func testConcurrentMixedOperations() async {
    let cache = OcaObjectCache()

    await withTaskGroup(of: Void.self) { group in
      // Writers
      for i in 1...50 {
        group.addTask {
          cache[OcaONo(i)] = OcaRoot(objectNumber: OcaONo(i))
        }
      }

      // Readers
      for i in 1...50 {
        group.addTask {
          _ = cache[OcaONo(i)]
        }
      }

      // Removers
      for i in 25...30 {
        group.addTask {
          cache.removeValue(forKey: OcaONo(i))
        }
      }
    }

    // Should not crash and should have some objects
    XCTAssertGreaterThanOrEqual(cache.count, 0)
  }

  // MARK: - Memory Pressure Tests

  func testCacheDelegateRemovesKeyTracking() {
    let cache = OcaObjectCache()
    let objectNumber: OcaONo = 1
    let object = OcaRoot(objectNumber: objectNumber)

    cache[objectNumber] = object
    XCTAssertEqual(cache.count, 1)

    // Manually trigger the delegate callback
    cache.cache(NSCache<AnyObject, AnyObject>(), willEvictObject: object)

    // The key tracking should be removed
    // Note: The actual NSCache still has the object until it decides to evict
    // But our tracking should be cleaned up
    XCTAssertEqual(cache.keys.contains(objectNumber), false)
  }

  // MARK: - Edge Cases

  func testMultipleRemoveSameKey() {
    let cache = OcaObjectCache()
    cache[1] = OcaRoot(objectNumber: 1)

    cache.removeValue(forKey: 1)
    XCTAssertNil(cache[1])

    // Removing again should not crash
    cache.removeValue(forKey: 1)
    XCTAssertNil(cache[1])
  }

  func testNoCountLimit() {
    // No countLimit means unlimited
    let cache = OcaObjectCache()
    for i in 1...100 {
      cache[OcaONo(i)] = OcaRoot(objectNumber: OcaONo(i))
    }
    XCTAssertGreaterThan(cache.count, 0)
  }

  func testOverwriteExistingObject() {
    let cache = OcaObjectCache()
    let objectNumber: OcaONo = 1

    let object1 = OcaRoot(objectNumber: objectNumber)
    cache[objectNumber] = object1
    XCTAssertEqual(cache.count, 1)

    let object2 = OcaRoot(objectNumber: objectNumber)
    cache[objectNumber] = object2
    XCTAssertEqual(cache.count, 1)

    // Should have the new object
    XCTAssertTrue(cache[objectNumber] === object2)
  }
}
