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
    try! presentationAddress
  }

  var bytes: [UInt8] {
    var storage = asStorage()
    return withUnsafeBytes(of: &storage) { Array($0.prefix(Int(size))) }
  }
}
