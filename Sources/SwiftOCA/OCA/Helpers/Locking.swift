import Synchronization

extension Mutex {
  var criticalValue: Value {
    withLock { $0 }
  }
}
