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

#if canImport(FlyingSocks)
// this is really here to deal with the fact we can't import SocketAddress and
// FlyingSocks at the same time
package extension sockaddr {
  var unsafelyUnwrappedPresentationAddress: String {
    try! presentationAddress
  }
}

package extension sockaddr_in {
  var unsafelyUnwrappedPresentationAddress: String {
    try! presentationAddress
  }
}

package extension sockaddr_in6 {
  var unsafelyUnwrappedPresentationAddress: String {
    try! presentationAddress
  }
}

package extension sockaddr_un {
  var unsafelyUnwrappedPresentationAddress: String {
    try! presentationAddress
  }
}
#endif

package extension SocketAddress {
  var unsafelyUnwrappedPresentationAddress: String {
    try! presentationAddress
  }
}
