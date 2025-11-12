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
