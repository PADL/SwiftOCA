import Synchronization

extension Mutex {
  package var criticalValue: Value {
    withLock { $0 }
  }
}
