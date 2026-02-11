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

@preconcurrency
import Foundation

final class OcaObjectCache: NSObject, @unchecked Sendable, NSCacheDelegate {
  private let _cache = NSCache<NSNumber, OcaRoot>()
  private let _objectNumbers = Mutex(Set<OcaONo>())

  override init() {
    super.init()
    _cache.delegate = self
  }

  convenience init(countLimit: Int) {
    self.init()
    if countLimit > 0 {
      _cache.countLimit = countLimit
    }
  }

  subscript(key: OcaONo) -> OcaRoot? {
    get {
      _cache.object(forKey: NSNumber(value: key))
    }
    set {
      if let newValue {
        _cache.setObject(newValue, forKey: NSNumber(value: key))
        _ = _objectNumbers.withLock { $0.insert(key) }
      } else {
        _cache.removeObject(forKey: NSNumber(value: key))
        _ = _objectNumbers.withLock { $0.remove(key) }
      }
    }
  }

  var count: Int {
    _objectNumbers.withLock { $0.count }
  }

  var keys: Set<OcaONo> {
    _objectNumbers.withLock { $0 }
  }

  var values: [OcaRoot] {
    let keysCopy = _objectNumbers.withLock { $0 }
    return keysCopy.compactMap { _cache.object(forKey: NSNumber(value: $0)) }
  }

  func removeAll() {
    _cache.removeAllObjects()
    _objectNumbers.withLock { $0.removeAll() }
  }

  func removeValue(forKey key: OcaONo) {
    _cache.removeObject(forKey: NSNumber(value: key))
    _ = _objectNumbers.withLock { $0.remove(key) }
  }

  fileprivate func removeKeyTracking(for key: OcaONo) {
    _ = _objectNumbers.withLock { $0.remove(key) }
  }

  func cache(
    _ cache: NSCache<AnyObject, AnyObject>,
    willEvictObject obj: Any
  ) {
    if let object = obj as? OcaRoot {
      removeKeyTracking(for: object.objectNumber)
    }
  }
}

// MARK: - Sequence Conformance

extension OcaObjectCache: Sequence {
  func makeIterator() -> AnyIterator<(key: OcaONo, value: OcaRoot)> {
    let keysCopy = _objectNumbers.withLock { $0 }
    var iterator = keysCopy.makeIterator()
    return AnyIterator {
      guard let key = iterator.next(),
            let value = self[key]
      else {
        return nil
      }
      return (key, value)
    }
  }
}
