#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

package struct ContinuousClockReference: Sendable {
  let dateReference = Date()
  let continuousClockReferenceInstant = ContinuousClock.now

  func date(for targetInstant: ContinuousClock.Instant) -> Date {
    let durationSinceReference = targetInstant - continuousClockReferenceInstant
    return dateReference + durationSinceReference.timeInterval
  }
}

package extension Duration {
  var seconds: Int64 {
    components.seconds
  }

  var milliseconds: Int64 {
    components.seconds * 1000 + Int64(Double(components.attoseconds) * 1e-15)
  }

  var timeInterval: TimeInterval {
    TimeInterval(components.seconds) + TimeInterval(components.attoseconds) * 1e-18
  }
}

package extension ContinuousClock {
  // a time in the past that's at least N seconds before the current time, where
  // N is the largest heartbeat value we are likely to see. we can use .epoch
  // when it is available.
  static var recentPast: ContinuousClock.Instant {
    now - .seconds(60)
  }
}
