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

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
@_spi(SwiftOCAPrivate) import SwiftOCA
import XCTest

/// A recipient of a notification, such as a controller in the device's own process, can
/// read which event it is and which property changed without decoding the value.
final class NotificationEventDataTests: XCTestCase {
  private let event = OcaEvent(emitterONo: 0x1000_0001, eventID: OcaPropertyChangedEventID)

  private func notification(format: OcaParameterFormat) throws -> Ocp1Notification2 {
    let changed = OcaPropertyChangedEventData<OcaFloat32>(
      propertyID: OcaPropertyID("4.1"), propertyValue: -6, changeType: .currentChanged
    )
    return Ocp1Notification2(
      event: event,
      notificationType: .event,
      eventData: try OcaEventDataCoding.encodeEventData(changed, format: format)
    )
  }

  func testTheEventAndChangedPropertyAreReadFromAnOcp1Notification() throws {
    let notification = try notification(format: .ocp1)
    XCTAssertEqual(notification.event, event)
    XCTAssertEqual(try OcaEventDataCoding.propertyID(from: notification.eventData), OcaPropertyID("4.1"))
  }

  #if NonEmbeddedBuild
  func testTheEventAndChangedPropertyAreReadFromAnOcp2Notification() throws {
    let notification = try notification(format: .ocp2)
    XCTAssertEqual(notification.event, event)
    XCTAssertEqual(try OcaEventDataCoding.propertyID(from: notification.eventData), OcaPropertyID("4.1"))
  }
  #endif
}
