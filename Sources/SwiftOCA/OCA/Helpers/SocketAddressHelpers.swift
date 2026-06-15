#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import SocketAddress

/// The parsed device-address type the socket backends store (see
/// `Ocp1MutableSocketAddressConnection`). Aliased here — in a file that imports
/// the PADL `SocketAddress` package cleanly — so a backend whose own file vends a
/// conflicting `SocketAddress` (FlyingSocks) can still name the storage type
/// without importing the package and triggering the clash.
@_spi(SwiftOCAPrivate)
public typealias _DeviceSocketAddress = AnySocketAddress

package extension Data {
  var socketPresentationAddress: String? {
    guard let socketAddress = try? AnySocketAddress(bytes: Array(self)) else { return nil }
    return try? socketAddress.presentationAddress
  }
}

package extension SocketAddress {
  var _presentationAddress: String {
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
