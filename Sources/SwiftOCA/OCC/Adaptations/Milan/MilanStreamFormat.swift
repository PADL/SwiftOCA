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

/// The AAF and CRF stream formats AES70-22 admits (Annex D, Tables 12/13), mapped onto
/// OcaMediaStreamMode and OcaMediaStreamModeCapability.
public struct MilanStreamFormat: Hashable, Sendable {
  public enum Kind: Hashable, Sendable {
    case aaf
    case crf
  }

  public var kind: Kind
  public var sampleRate: OcaFrequency
  /// Channels per frame; zero for CRF.
  public var channelCount: OcaUint16
  /// The AAF "ut" bit: the stream may carry from one up to `channelCount` channels.
  public var upTo: Bool

  public init(kind: Kind, sampleRate: OcaFrequency, channelCount: OcaUint16 = 0, upTo: Bool = false) {
    self.kind = kind
    self.sampleRate = sampleRate
    self.channelCount = channelCount
    self.upTo = upTo
  }

  public static func aaf(sampleRate: OcaFrequency, channelCount: OcaUint16, upTo: Bool = false)
    -> MilanStreamFormat
  {
    MilanStreamFormat(kind: .aaf, sampleRate: sampleRate, channelCount: channelCount, upTo: upTo)
  }

  public static func crf(sampleRate: OcaFrequency) -> MilanStreamFormat {
    MilanStreamFormat(kind: .crf, sampleRate: sampleRate)
  }

  public static let sampleRates: [OcaFrequency] = [48000, 96000, 192_000]
  public static let aafChannelCounts: [OcaUint16] = [1, 2, 4, 6, 8]

  /// The fixed-channel-count AAF formats of Annex D plus a CRF format per rate.
  public static let supported: [MilanStreamFormat] = sampleRates.flatMap { rate in
    aafChannelCounts.map { .aaf(sampleRate: rate, channelCount: $0) } + [.crf(sampleRate: rate)]
  }

  public var mediaStreamMode: OcaMediaStreamMode {
    switch kind {
    case .aaf:
      OcaMediaStreamMode(
        frameFormat: .aaf,
        encodingType: MilanAdaptation.aafEncodingType,
        samplingRate: sampleRate,
        channelCount: channelCount,
        packetTime: MilanAdaptation.packetTime
      )
    case .crf:
      OcaMediaStreamMode(
        frameFormat: .crf_milan,
        encodingType: "",
        samplingRate: sampleRate,
        channelCount: 0,
        packetTime: MilanAdaptation.packetTime
      )
    }
  }

  public init?(mediaStreamMode mode: OcaMediaStreamMode) {
    switch mode.frameFormat {
    case .aaf:
      guard mode.encodingType == MilanAdaptation.aafEncodingType else { return nil }
      self = .aaf(sampleRate: mode.samplingRate, channelCount: mode.channelCount)
    case .crf_milan:
      self = .crf(sampleRate: mode.samplingRate)
    default:
      return nil
    }
  }

  public func mediaStreamModeCapability(
    id: OcaID16,
    direction: OcaMediaStreamModeCapabilityDirection
  ) -> OcaMediaStreamModeCapability {
    switch kind {
    case .aaf:
      OcaMediaStreamModeCapability(
        id: id,
        name: "",
        direction: direction,
        frameFormatList: [.aaf],
        encodingTypeList: [MilanAdaptation.aafEncodingType],
        samplingRateList: [sampleRate],
        channelCountList: upTo ? [] : [channelCount],
        channelCountRange: upTo ? 1...channelCount : 0...0,
        packetTimeList: [MilanAdaptation.packetTime],
        packetTimeRange: 0...0
      )
    case .crf:
      OcaMediaStreamModeCapability(
        id: id,
        name: "",
        direction: direction,
        frameFormatList: [.crf_milan],
        encodingTypeList: [],
        samplingRateList: [sampleRate],
        channelCountList: [0],
        channelCountRange: 0...0,
        packetTimeList: [MilanAdaptation.packetTime],
        packetTimeRange: 0...0
      )
    }
  }
}
