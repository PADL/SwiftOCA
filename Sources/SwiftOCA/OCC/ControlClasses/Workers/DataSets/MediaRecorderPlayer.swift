//
// Copyright (c) 2025 PADL Software Pty Ltd
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

@OcaClass
open class OcaMediaRecorderPlayer: OcaDatasetWorker, @unchecked Sendable {
  override open class var classID: OcaClassID { OcaClassID("1.1.7.1") }
  override open class var classVersion: OcaClassVersionNumber { 3 }

  @OcaProperty(
    propertyID: OcaPropertyID("4.1"),
    getMethodID: OcaMethodID("4.7")
  )
  public var state: OcaProperty<OcaMediaRecorderPlayerState>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("4.2"),
    getMethodID: OcaMethodID("4.8"),
    setMethodID: OcaMethodID("4.9")
  )
  public var trackCount: OcaProperty<OcaUint16>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("4.3"),
    getMethodID: OcaMethodID("4.10"),
    setMethodID: OcaMethodID("4.11"),
    ocp2GetName: "Functions",
    ocp2SetName: "Functions"
  )
  public var trackFunctions: OcaProperty<[OcaMediaTrackFunction]>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("4.4"),
    getMethodID: OcaMethodID("4.12"),
    setMethodID: OcaMethodID("4.13"),
    ocp2GetName: "Option",
    ocp2SetName: "Option"
  )
  public var playOption: OcaProperty<OcaMediaPlayOption>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("4.5")
  )
  public var windowStart: OcaProperty<OcaMediaVolumePosition>.PropertyValue

  @OcaProperty(
    propertyID: OcaPropertyID("4.6")
  )
  public var windowEnd: OcaProperty<OcaMediaVolumePosition>.PropertyValue

  /// Opens a session on the media volume `datasetONo` for playing or recording, under
  /// `lockState`.
  @OcaMethod("4.1", name: "Open", parameterNames: ["DatasetONo", "AccessMode", "LockState"])
  public func open(
    datasetONo: OcaONo,
    accessMode: OcaMediaAccessMode,
    lockState: OcaLockState
  ) async throws

  /// Closes the session on the open media volume.
  @OcaMethod("4.2", name: "Close")
  public func close() async throws

  /// Records over the window from the current position, at once.
  @OcaMethod("4.3", name: "Record")
  public func record() async throws

  /// Plays the window from the current position, at once.
  @OcaMethod("4.4", name: "Play")
  public func play() async throws

  /// Stops at once, leaving the session open and the position one past the last frame
  /// accessed.
  @OcaMethod("4.5", name: "Stop")
  public func stop() async throws

  /// Stops at once, sets the window to the whole volume, the position to its start and
  /// the play option to normal; the track functions are kept.
  @OcaMethod("4.6", name: "Reset")
  public func reset() async throws

  /// Sets the open volume's track count; only a volume open for recording has one to set.
  @OcaMethod("4.9", name: "SetTrackCount", parameterNames: ["TrackCount"])
  public func setTrackCount(trackCount: OcaUint16) async throws

  /// Sets each track's functions; a volume must be open.
  @OcaMethod("4.11", name: "SetTrackFunctions", parameterNames: ["Functions"])
  public func setTrackFunctions(functions: [OcaMediaTrackFunction]) async throws

  @OcaMethod("4.13", name: "SetPlayOption", parameterNames: ["Option"])
  public func setPlayOption(option: OcaMediaPlayOption) async throws

  /// The position relative to the window's start; refused with no volume open.
  @OcaMethod("4.14", name: "GetPosition", resultNames: ["Position"])
  public func getPosition() async throws -> OcaMediaVolumePosition

  /// Moves to `position`, relative to the window's start.
  @OcaMethod("4.15", name: "SetPosition", parameterNames: ["Position"])
  public func setPosition(position: OcaMediaVolumePosition) async throws

  /// The window's first and last positions (WindowStart and WindowEnd).
  public struct WindowRange: OcaParametersReflectable, Equatable {
    public let firstPosition: OcaMediaVolumePosition
    public let lastPosition: OcaMediaVolumePosition

    public init(firstPosition: OcaMediaVolumePosition, lastPosition: OcaMediaVolumePosition) {
      self.firstPosition = firstPosition
      self.lastPosition = lastPosition
    }
  }

  @OcaMethod("4.16", name: "GetWindowRange", resultNames: ["FirstPosition", "LastPosition"])
  public func getWindowRange() async throws -> WindowRange

  @OcaMethod("4.17", name: "SetWindowRange", parameterNames: ["FirstPosition", "LastPosition"])
  public func setWindowRange(
    firstPosition: OcaMediaVolumePosition,
    lastPosition: OcaMediaVolumePosition
  ) async throws
}
