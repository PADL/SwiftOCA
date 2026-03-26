#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SocketAddress

package extension Data {
  var socketPresentationAddress: String? {
    guard let socketAddress = try? AnySocketAddress(bytes: Array(self)) else { return nil }
    return try? socketAddress.presentationAddress
  }
}

package extension SocketAddress {
  var unsafelyUnwrappedPresentationAddress: String {
    (try? presentationAddress) ?? "unknown"
  }

  var bytes: [UInt8] {
    withSockAddr { sa, size in
      let buffer = UnsafeBufferPointer(
        start: UnsafePointer<UInt8>(OpaquePointer(sa)),
        count: Int(size)
      )
      return Array(buffer)
    }
  }

  var data: Data {
    Data(bytes)
  }
}
