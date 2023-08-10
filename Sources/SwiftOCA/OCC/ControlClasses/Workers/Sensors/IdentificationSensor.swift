//
// Copyright (c) 2023 PADL Software Pty Ltd
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

open class OcaIdentificationSensor: OcaSensor {
    override open class var classID: OcaClassID { OcaClassID("1.1.2.6") }

    public static let identifyEventID = OcaEventID(defLevel: 4, eventIndex: 1)

    public func onIdentify(_ callback: @escaping AES70SubscriptionCallback) async throws {
        guard let connectionDelegate else { throw Ocp1Error.noConnectionDelegate }
        let event = OcaEvent(emitterONo: objectNumber, eventID: Self.identifyEventID)

        try await connectionDelegate.addSubscription(event: event, callback: callback)
    }
}
