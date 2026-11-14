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

import Foundation
@testable import SwiftOCA
import Testing

/// OcaMediaRecorderPlayer's types and method IDs, as the AES70 class model has them.
@Suite struct MediaRecorderPlayerTypeTests {
  @Test func aSamplePositionIsItsTypeThenACount() throws {
    let position = OcaMediaVolumePosition.samples(48000)
    let encoded: Data = try Ocp1Encoder().encode(position)
    #expect(encoded == Data([0x00, 0x00, 0, 0, 0, 0, 0, 0, 0xBB, 0x80]))
    #expect(try Ocp1Decoder().decode(OcaMediaVolumePosition.self, from: encoded) == position)
    #expect(position.samples == 48000)
    #expect(position.seconds == nil)
  }

  @Test func aTimePositionCarriesBinary64Seconds() throws {
    let position = OcaMediaVolumePosition.seconds(1.5)
    let encoded: Data = try Ocp1Encoder().encode(position)
    #expect(encoded == Data([0x00, 0x01, 0x3F, 0xF8, 0, 0, 0, 0, 0, 0]))
    let decoded = try Ocp1Decoder().decode(OcaMediaVolumePosition.self, from: encoded)
    #expect(decoded.seconds == 1.5)
    #expect(decoded.samples == nil)
  }

  @Test func aWindowRangeIsItsFirstThenItsLastPosition() throws {
    let range = OcaMediaRecorderPlayer.WindowRange(firstPosition: .samples(1), lastPosition: .samples(2))
    let encoded: Data = try Ocp1Encoder().encode(range)
    #expect(encoded == Data([0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2]))
    #expect(try Ocp1Decoder().decode(OcaMediaRecorderPlayer.WindowRange.self, from: encoded) == range)
  }

  @Test func theEnumerationsAndTrackFunctionsHaveTheModelsValues() {
    #expect(OcaMediaRecorderPlayerState.playing.rawValue == 4)
    #expect(OcaMediaPlayOption.repeatInterval.rawValue == 2)
    #expect(OcaMediaAccessMode.record.rawValue == 2)
    #expect(OcaMediaVolumePositionType.seconds.rawValue == 1)
    #expect(OcaMediaTrackFunctionPlayInPlayMode == 1)
    #expect(OcaMediaTrackFunctionPlayInRecordMode == 2)
    #expect(OcaMediaTrackFunctionRecordInRecordMode == 4)
  }

  @Test func theMethodsHaveTheModelsIDsAndNames() {
    typealias Methods = OcaMediaRecorderPlayer.Methods
    let methods: [(OcaAnyMethodDescriptor, String, String)] = [
      (Methods.open.erased, "4.1", "Open"),
      (Methods.close.erased, "4.2", "Close"),
      (Methods.record.erased, "4.3", "Record"),
      (Methods.play.erased, "4.4", "Play"),
      (Methods.stop.erased, "4.5", "Stop"),
      (Methods.reset.erased, "4.6", "Reset"),
      (Methods.setTrackCount.erased, "4.9", "SetTrackCount"),
      (Methods.setTrackFunctions.erased, "4.11", "SetTrackFunctions"),
      (Methods.setPlayOption.erased, "4.13", "SetPlayOption"),
      (Methods.getPosition.erased, "4.14", "GetPosition"),
      (Methods.setPosition.erased, "4.15", "SetPosition"),
      (Methods.getWindowRange.erased, "4.16", "GetWindowRange"),
      (Methods.setWindowRange.erased, "4.17", "SetWindowRange"),
    ]
    for (method, id, name) in methods {
      #expect(method.methodID == OcaMethodID(id), "\(name)")
      #expect(method.name == name)
    }
    #expect(Methods.open.erased.parameterNames == ["DatasetONo", "AccessMode", "LockState"])
    #expect(Methods.getWindowRange.erased.resultNames == ["FirstPosition", "LastPosition"])
    #expect(OcaMediaRecorderPlayer.classID == OcaClassID("1.1.7.1"))
    #expect(OcaDatasetWorker.classID == OcaClassID("1.1.7"))
  }
}
