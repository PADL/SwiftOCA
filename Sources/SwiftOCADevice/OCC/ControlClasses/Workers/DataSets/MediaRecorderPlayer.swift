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

@_spi(SwiftOCAPrivate)
import SwiftOCA

/// A player and recorder of media volumes, datasets of media data (AES70
/// `OcaMediaRecorderPlayer`, class 1.1.7.1). Opening, the transport and the position are
/// device specific: those methods are refused `NotImplemented` until a subclass overrides
/// them. The setters of the play option, the track functions and the window keep the value
/// given, as the model describes; a subclass that applies them elsewhere overrides them too.
@OcaDeviceClass
open class OcaMediaRecorderPlayer: OcaDatasetWorker {
  override open class var classID: OcaClassID { OcaClassID("1.1.7.1") }
  override open class var classVersion: OcaClassVersionNumber { 3 }

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("4.1"),
    getMethodID: OcaMethodID("4.7")
  )
  public var state: OcaMediaRecorderPlayerState = .idle

  /// The open volume's track count; zero with none open.
  @OcaDeviceProperty(
    propertyID: OcaPropertyID("4.2"),
    getMethodID: OcaMethodID("4.8"),
    setMethodID: OcaMethodID("4.9")
  )
  public var trackCount: OcaUint16 = 0

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("4.3"),
    getMethodID: OcaMethodID("4.10"),
    setMethodID: OcaMethodID("4.11"),
    ocp2GetName: "Functions",
    ocp2SetName: "Functions"
  )
  public var trackFunctions = [OcaMediaTrackFunction]()

  @OcaDeviceProperty(
    propertyID: OcaPropertyID("4.4"),
    getMethodID: OcaMethodID("4.12"),
    setMethodID: OcaMethodID("4.13"),
    ocp2GetName: "Option",
    ocp2SetName: "Option"
  )
  public var playOption: OcaMediaPlayOption = .normal

  /// The window's first position; GetWindowRange and SetWindowRange read and write it.
  @OcaDeviceProperty(
    propertyID: OcaPropertyID("4.5")
  )
  public var windowStart = OcaMediaVolumePosition.samples(0)

  /// The window's last position; GetWindowRange and SetWindowRange read and write it.
  @OcaDeviceProperty(
    propertyID: OcaPropertyID("4.6")
  )
  public var windowEnd = OcaMediaVolumePosition.samples(0)

  @OcaDeviceMethod(SwiftOCA.OcaMediaRecorderPlayer.Methods.open)
  open func open(
    datasetONo: OcaONo,
    accessMode: OcaMediaAccessMode,
    lockState: OcaLockState,
    from controller: any OcaController
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaRecorderPlayer.Methods.close)
  open func close(from controller: any OcaController) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaRecorderPlayer.Methods.record, access: .write)
  open func record(from controller: any OcaController) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaRecorderPlayer.Methods.play, access: .write)
  open func play(from controller: any OcaController) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaRecorderPlayer.Methods.stop)
  open func stop(from controller: any OcaController) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaRecorderPlayer.Methods.reset)
  open func reset(from controller: any OcaController) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  /// Only a volume open for recording has a track count to set, and recording is device
  /// specific.
  @OcaDeviceMethod(SwiftOCA.OcaMediaRecorderPlayer.Methods.setTrackCount)
  open func setTrackCount(trackCount: OcaUint16, from controller: any OcaController) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  /// Refused `InvalidRequest` with no volume open.
  @OcaDeviceMethod(SwiftOCA.OcaMediaRecorderPlayer.Methods.setTrackFunctions)
  open func setTrackFunctions(
    functions: [OcaMediaTrackFunction],
    from controller: any OcaController
  ) async throws {
    guard state != .idle else { throw Ocp1Error.status(.invalidRequest) }
    trackFunctions = functions
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaRecorderPlayer.Methods.setPlayOption)
  open func setPlayOption(
    option: OcaMediaPlayOption,
    from controller: any OcaController
  ) async throws {
    playOption = option
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaRecorderPlayer.Methods.getPosition)
  open func getPosition(from controller: any OcaController) async throws -> OcaMediaVolumePosition {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaRecorderPlayer.Methods.setPosition)
  open func setPosition(
    position: OcaMediaVolumePosition,
    from controller: any OcaController
  ) async throws {
    throw Ocp1Error.status(.notImplemented)
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaRecorderPlayer.Methods.getWindowRange)
  open func getWindowRange(from controller: any OcaController) async throws
    -> SwiftOCA.OcaMediaRecorderPlayer.WindowRange
  {
    .init(firstPosition: windowStart, lastPosition: windowEnd)
  }

  @OcaDeviceMethod(SwiftOCA.OcaMediaRecorderPlayer.Methods.setWindowRange)
  open func setWindowRange(
    firstPosition: OcaMediaVolumePosition,
    lastPosition: OcaMediaVolumePosition,
    from controller: any OcaController
  ) async throws {
    windowStart = firstPosition
    windowEnd = lastPosition
  }
}
