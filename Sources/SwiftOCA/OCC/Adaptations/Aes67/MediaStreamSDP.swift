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

/// The subset of an AES67 audio session description that the transports exchange:
/// RFC 4566 with the RFC 7273 clock attributes AES67 §8 requires.
public struct MediaStreamSDP: Sendable, Equatable {
  public enum Direction: String, Sendable {
    case sendOnly = "sendonly"
    case receiveOnly = "recvonly"
    case sendAndReceive = "sendrecv"
  }

  /// Identity of the session, unique with `originAddress` for its lifetime.
  public let sessionID: UInt64
  /// Incremented by the sender whenever the description changes.
  public let sessionVersion: UInt64
  /// Address of the host that authored the description.
  public let originAddress: String
  public let sessionName: String
  /// Free text about the stream, the "i=" line; AES70-21 carries it as MediaInfo.
  public let sessionInformation: String?
  /// Where the stream is sent: a multicast group, or the receiver for a unicast stream.
  public var destinationAddress: String
  public var destinationPort: UInt16
  /// Multicast scope, omitted from the connection line when nil.
  public let timeToLive: UInt8?
  /// The address the stream is sent from, when the description filters on it (RFC 4570).
  public var sourceAddress: String?
  public let payloadType: UInt8
  /// Bits per sample, carried in the encoding name as L16, L24 or L32.
  public let sampleSize: UInt8
  public let sampleRate: UInt32
  public let channelCount: UInt16
  /// Packet duration in seconds.
  public let packetTime: TimeInterval
  /// Grandmaster identity as the eight hyphen-separated octets of RFC 7273 §4.8.
  public let ptpGrandmasterID: String?
  public let ptpDomain: UInt8?
  /// RTP timestamp of the media clock's zero point.
  public let mediaClockOffset: UInt32?
  public var direction: Direction

  public init(
    sessionID: UInt64,
    sessionVersion: UInt64,
    originAddress: String,
    sessionName: String,
    sessionInformation: String? = nil,
    destinationAddress: String,
    destinationPort: UInt16,
    timeToLive: UInt8? = nil,
    sourceAddress: String? = nil,
    payloadType: UInt8,
    sampleSize: UInt8,
    sampleRate: UInt32,
    channelCount: UInt16,
    packetTime: TimeInterval,
    ptpGrandmasterID: String? = nil,
    ptpDomain: UInt8? = nil,
    mediaClockOffset: UInt32? = nil,
    direction: Direction
  ) {
    self.sessionID = sessionID
    self.sessionVersion = sessionVersion
    self.originAddress = originAddress
    self.sessionName = sessionName
    self.sessionInformation = sessionInformation
    self.destinationAddress = destinationAddress
    self.destinationPort = destinationPort
    self.timeToLive = timeToLive
    self.sourceAddress = sourceAddress
    self.payloadType = payloadType
    self.sampleSize = sampleSize
    self.sampleRate = sampleRate
    self.channelCount = channelCount
    self.packetTime = packetTime
    self.ptpGrandmasterID = ptpGrandmasterID
    self.ptpDomain = ptpDomain
    self.mediaClockOffset = mediaClockOffset
    self.direction = direction
  }

  public var encodingName: String { "L\(sampleSize)" }

  /// The AES70 media stream mode this description carries.
  public var mediaStreamMode: OcaMediaStreamMode {
    OcaMediaStreamMode(
      frameFormat: .rtp,
      encodingType: "audio/\(encodingName)",
      samplingRate: OcaFrequency(sampleRate),
      channelCount: channelCount,
      packetTime: OcaTimeInterval(packetTime)
    )
  }

  public var isMulticast: Bool { Self.isMulticast(destinationAddress) }

  /// Whether an address, IPv4 or IPv6 as text, is a multicast group.
  public static func isMulticast(_ address: String) -> Bool {
    if address.contains(":") { return address.lowercased().hasPrefix("ff") }
    guard let first = address.split(separator: ".").first, let octet = UInt8(first) else { return false }
    return (224...239).contains(octet)
  }
}

// MARK: - Rendering

public extension MediaStreamSDP {
  /// RFC 4566 text, with the CRLF line endings RFC 4566 §5 requires.
  var sdpString: OcaSDPString {
    var lines = [
      "v=0",
      "o=- \(sessionID) \(sessionVersion) IN IP4 \(originAddress)",
      "s=\(sessionName)",
    ]
    if let sessionInformation {
      lines.append("i=\(sessionInformation)")
    }
    // the connection line goes in the media section, as AES67 and ST 2110 senders have it
    // and as a description of more than one stream must
    lines += [
      "t=0 0",
      "m=audio \(destinationPort) RTP/AVP \(payloadType)",
      timeToLive.map { "c=IN IP4 \(destinationAddress)/\($0)" } ?? "c=IN IP4 \(destinationAddress)",
      "a=rtpmap:\(payloadType) \(encodingName)/\(sampleRate)/\(channelCount)",
      "a=ptime:\(Self.format(milliseconds: packetTime * 1000))",
    ]
    if let sourceAddress {
      lines.append("a=source-filter: incl IN IP4 \(destinationAddress) \(sourceAddress)")
    }
    if let ptpGrandmasterID {
      let domain = ptpDomain.map { ":\($0)" } ?? ""
      lines.append("a=ts-refclk:ptp=IEEE1588-2008:\(ptpGrandmasterID)\(domain)")
    }
    if let mediaClockOffset {
      lines.append("a=mediaclk:direct=\(mediaClockOffset)")
    }
    lines.append("a=\(direction.rawValue)")
    return lines.joined(separator: "\r\n") + "\r\n"
  }

  private static func format(milliseconds: Double) -> String {
    String(format: "%g", milliseconds)
  }
}

// MARK: - Parsing

public extension MediaStreamSDP {
  /// The session section followed by each media section, one description per stream, so
  /// a multistream description such as an ST 2022-7 pair can be read a stream at a time.
  static func streams(in sdpString: OcaSDPString) -> [OcaSDPString] {
    let (session, media) = sections(of: sdpString)
    return media.map { (session + $0).joined(separator: "\r\n") + "\r\n" }
  }

  /// AES70-21 §10.2.4 media description selection: the session section with the one media
  /// section `mediaIDType` and `mediaID` name. `.none` takes the only media section, and is
  /// refused for a description with more than one; otherwise `mediaID` must name exactly one.
  /// - Throws: `Ocp1Error.status(.badFormat)` for a description with no media section,
  ///   `.parameterError` when the identifier selects none.
  static func selectStream(
    in sdpString: OcaSDPString,
    mediaIDType: Aes67MediaIDType,
    mediaID: OcaString
  ) throws -> OcaSDPString {
    let (session, media) = sections(of: sdpString)
    guard !media.isEmpty else { throw Ocp1Error.status(.badFormat) }
    let index: Int
    if mediaIDType == .none {
      guard media.count == 1 else { throw Ocp1Error.status(.parameterError) }
      index = 0
    } else {
      // an identifier that more than one media description has selects none
      let wanted = canonical(mediaID, as: mediaIDType)
      let found = media.indices.filter {
        identifier(mediaIDType, of: media[$0], at: $0, session: session) == wanted
      }
      guard wanted != nil, found.count == 1 else { throw Ocp1Error.status(.parameterError) }
      index = found[0]
    }
    return (session + media[index]).joined(separator: "\r\n") + "\r\n"
  }

  /// The identifier of `type` that the media section at `index` (from zero) of a description
  /// has, as AES70-21 §10.2.4 spells it; nil when it has none, and for `.none` and
  /// `.transportAddress6`, which AES67 does not use.
  static func mediaID(
    _ type: Aes67MediaIDType,
    ofStreamAt index: Int,
    in sdpString: OcaSDPString
  ) -> OcaString? {
    let (session, media) = sections(of: sdpString)
    guard media.indices.contains(index) else { return nil }
    return identifier(type, of: media[index], at: index, session: session)
  }

  private static func identifier(
    _ type: Aes67MediaIDType,
    of section: [Substring],
    at index: Int,
    session: [Substring]
  ) -> OcaString? {
    switch type {
    case .ordinal: String(index + 1)
    case .label: attribute("label", in: section)
    case .mid: attribute("mid", in: section)
    case .portNo: port(of: section).map(String.init)
    case .transportAddress4:
      // the media section's connection line, else the session's (RFC 4566 §5.7)
      ip4Address(in: section.contains { $0.hasPrefix("c=") } ? section : session).flatMap { address in
        port(of: section).map { "\(address):\($0)" }
      }
    case .none, .transportAddress6: nil
    }
  }

  /// `mediaID` as `identifier` spells it: numbers in decimal without leading zeros.
  private static func canonical(_ mediaID: OcaString, as type: Aes67MediaIDType) -> OcaString? {
    switch type {
    case .ordinal, .portNo:
      return UInt(mediaID).map(String.init)
    case .transportAddress4:
      guard let colon = mediaID.lastIndex(of: ":"),
            let port = UInt16(mediaID[mediaID.index(after: colon)...]) else { return nil }
      return "\(mediaID[..<colon]):\(port)"
    default:
      return mediaID
    }
  }

  /// The value of a section's first `a=<name>:<value>` attribute.
  private static func attribute(_ name: String, in section: [Substring]) -> OcaString? {
    let prefix = "a=\(name):"
    return section.first { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
  }

  /// A media section's `m=` port: `m=<media> <port>[/<count>] <proto> <fmt>`.
  private static func port(of section: [Substring]) -> UInt16? {
    let fields = section.first?.dropFirst(2).split(separator: " ") ?? []
    return fields.count > 1 ? fields[1].split(separator: "/").first.flatMap { UInt16($0) } : nil
  }

  /// The address of a section's `c=IN IP4 <address>[/<ttl>]` line.
  private static func ip4Address(in section: [Substring]) -> OcaString? {
    guard let line = section.first(where: { $0.hasPrefix("c=") }) else { return nil }
    let fields = line.dropFirst(2).split(separator: " ")
    guard fields.count >= 3, fields[1] == "IP4" else { return nil }
    return fields[2].split(separator: "/").first.map(String.init)
  }

  private static func sections(
    of sdpString: OcaSDPString
  ) -> (session: [Substring], media: [[Substring]]) {
    var session = [Substring]()
    var media = [[Substring]]()
    for line in sdpString.split(whereSeparator: \.isNewline) {
      if line.hasPrefix("m=") {
        media.append([line])
      } else if media.isEmpty {
        session.append(line)
      } else {
        media[media.count - 1].append(line)
      }
    }
    return (session, media)
  }
}

public extension MediaStreamSDP {
  /// Reads the fields AES67 requires; returns nil when any of them is absent or malformed.
  init?(sdpString: OcaSDPString) {
    var origin: (sessionID: UInt64, version: UInt64, address: String)?
    var sessionName = ""
    var sessionInformation: String?
    var connection: (address: String, ttl: UInt8?)?
    var media: (port: UInt16, payloadType: UInt8)?
    var rtpmap: (payloadType: UInt8, sampleSize: UInt8, rate: UInt32, channels: UInt16)?
    var packetTime: TimeInterval?
    var grandmasterID: String?
    var domain: UInt8?
    var clockOffset: UInt32?
    var direction = Direction.sendOnly
    var sourceAddress: String?

    // a CRLF pair is one Character, so match any newline rather than its parts
    for line in sdpString.split(whereSeparator: \.isNewline) {
      let value = String(line.dropFirst(2))
      switch line.prefix(2) {
      case "o=":
        // <username> <session id> <version> IN IP4 <address>
        let fields = value.split(separator: " ")
        guard fields.count >= 6, let id = UInt64(fields[1]), let version = UInt64(fields[2])
        else { return nil }
        origin = (id, version, String(fields[5]))
      case "s=":
        sessionName = value
      case "i=":
        sessionInformation = value
      case "c=":
        // IN IP4 <address>[/<ttl>]
        let fields = value.split(separator: " ")
        guard fields.count >= 3 else { return nil }
        let address = fields[2].split(separator: "/")
        guard let host = address.first else { return nil }
        connection = (String(host), address.count > 1 ? UInt8(address[1]) : nil)
      case "m=":
        // audio <port> RTP/AVP <payload type>
        let fields = value.split(separator: " ")
        guard fields.count >= 4, fields[0] == "audio", let port = UInt16(fields[1]),
              let payloadType = UInt8(fields[3]) else { return nil }
        media = (port, payloadType)
      case "a=":
        Self.parse(attribute: value, rtpmap: &rtpmap, packetTime: &packetTime,
                   grandmasterID: &grandmasterID, domain: &domain,
                   clockOffset: &clockOffset, direction: &direction, sourceAddress: &sourceAddress)
      default:
        break
      }
    }

    guard let origin, let connection, let media, let rtpmap, rtpmap.payloadType == media.payloadType
    else { return nil }
    // "inf" and "nan" read as numbers; what is computed from a packet time needs a real one
    if let packetTime, !(packetTime.isFinite && packetTime > 0) { return nil }

    self.init(
      sessionID: origin.sessionID,
      sessionVersion: origin.version,
      originAddress: origin.address,
      sessionName: sessionName,
      sessionInformation: sessionInformation,
      destinationAddress: connection.address,
      destinationPort: media.port,
      timeToLive: connection.ttl,
      sourceAddress: sourceAddress,
      payloadType: media.payloadType,
      sampleSize: rtpmap.sampleSize,
      sampleRate: rtpmap.rate,
      channelCount: rtpmap.channels,
      // AES67 §7 defaults to 1 ms when the description omits ptime
      packetTime: packetTime ?? 1e-3,
      ptpGrandmasterID: grandmasterID,
      ptpDomain: domain,
      mediaClockOffset: clockOffset,
      direction: direction
    )
  }

  private static func parse(
    attribute: String,
    rtpmap: inout (payloadType: UInt8, sampleSize: UInt8, rate: UInt32, channels: UInt16)?,
    packetTime: inout TimeInterval?,
    grandmasterID: inout String?,
    domain: inout UInt8?,
    clockOffset: inout UInt32?,
    direction: inout Direction,
    sourceAddress: inout String?
  ) {
    // <name>[:<value>]
    let parts = attribute.split(separator: ":", maxSplits: 1)
    let value = parts.count > 1 ? String(parts[1]) : nil
    switch (parts.first.map(String.init) ?? "", value) {
    case let ("rtpmap", value?):
      // <payload type> L<bits>/<rate>[/<channels>]
      let fields = value.split(separator: " ")
      guard fields.count >= 2, let payloadType = UInt8(fields[0]) else { return }
      let format = fields[1].split(separator: "/")
      guard format.count >= 2, format[0].hasPrefix("L"),
            let sampleSize = UInt8(format[0].dropFirst()),
            let rate = UInt32(format[1]) else { return }
      rtpmap = (payloadType, sampleSize, rate, format.count > 2 ? UInt16(format[2]) ?? 1 : 1)
    case let ("ptime", value?):
      if let milliseconds = Double(value) { packetTime = milliseconds / 1000 }
    case let ("ts-refclk", value?) where value.hasPrefix("ptp="):
      // ptp=<ptp version>:<grandmaster id>[:<domain>]
      let fields = value.dropFirst(4).split(separator: ":")
      guard fields.count >= 2 else { return }
      grandmasterID = String(fields[1])
      domain = fields.count > 2 ? UInt8(fields[2]) : nil
    case let ("mediaclk", value?) where value.hasPrefix("direct="):
      clockOffset = UInt32(value.dropFirst(7))
    case let ("source-filter", value?):
      // incl IN IP4 <destination> <source>...; an exclusion names no one source
      let fields = value.split(separator: " ")
      guard fields.count >= 5, fields[0] == "incl" else { return }
      sourceAddress = String(fields[4])
    case let (name, nil):
      if let parsed = Direction(rawValue: name) { direction = parsed }
    default:
      break
    }
  }
}
