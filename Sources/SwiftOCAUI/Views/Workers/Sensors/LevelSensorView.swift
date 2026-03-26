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

import SwiftOCA
import SwiftUI

// MARK: - IEC 60268-18 / EBU R.68 level meter ballistics

/// Applies PPM ballistics matching inferno_ui: 10ms EMA attack,
/// 14 dB/s linear decay.
@MainActor
private final class PPMBallistics: ObservableObject {
  /// Attack time constant (EMA filter): 10ms
  private static let attackTimeMs: Float = 10.0
  /// Fall rate: 14 dB/s
  private static let decayDBPerSec: Float = 14.0
  /// Display refresh rate
  private static let refreshInterval: TimeInterval = 1.0 / 60.0

  @Published var displayDB: Float = -144.0

  private var peakDB: Float = -144.0
  private var lastUpdate: Date = .now
  private var timer: Timer?

  func start() {
    guard timer == nil else { return }
    timer = Timer.scheduledTimer(
      withTimeInterval: Self.refreshInterval,
      repeats: true
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.tick()
      }
    }
  }

  func stop() {
    timer?.invalidate()
    timer = nil
  }

  func update(dB: Float) {
    peakDB = dB
  }

  private func tick() {
    let now = Date.now
    let deltaTimeMs = Float(now.timeIntervalSince(lastUpdate)) * 1000.0
    lastUpdate = now

    if peakDB > displayDB {
      // Attack: integrate using EMA filter
      let alpha = 1.0 - expf(-deltaTimeMs / Self.attackTimeMs)
      displayDB = alpha * peakDB + (1.0 - alpha) * displayDB
    } else {
      // Decay: linear fall at decayDBPerSec
      let decayDB = deltaTimeMs * Self.decayDBPerSec / 1000.0
      displayDB = max(peakDB, displayDB - decayDB)
    }
  }
}

// MARK: - Scale markings

/// IEC 60268-18 Type I scale markings (dBFS)
private let scaleMarks: [Float] = [0, -5, -10, -20, -30, -40, -50, -60]

// MARK: - Meter bar view

private struct LevelMeterBar: View {
  let dB: Float
  let minDB: Float
  let maxDB: Float

  private var fraction: CGFloat {
    let clamped = min(max(dB, minDB), maxDB)
    return CGFloat((clamped - minDB) / (maxDB - minDB))
  }

  private func colorForFraction(_ f: CGFloat) -> Color {
    if f > 0.9 { return .red }
    if f > 0.75 { return .orange }
    if f > 0.5 { return .yellow }
    return .green
  }

  var body: some View {
    GeometryReader { geo in
      ZStack(alignment: .bottom) {
        Rectangle()
          .fill(Color.primary.opacity(0.1))
        Rectangle()
          .fill(colorForFraction(fraction))
          .frame(height: geo.size.height * fraction)
          .animation(.linear(duration: 1.0 / 60.0), value: fraction)
      }
    }
    .frame(width: 16)
  }
}

private struct LevelMeterScale: View {
  let minDB: Float
  let maxDB: Float

  var body: some View {
    GeometryReader { geo in
      ForEach(scaleMarks, id: \.self) { mark in
        if mark >= minDB && mark <= maxDB {
          let frac = CGFloat((mark - minDB) / (maxDB - minDB))
          let y = geo.size.height * (1.0 - frac)
          Text("\(Int(mark))")
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(.secondary)
            .position(x: geo.size.width / 2, y: y)
        }
      }
    }
    .frame(width: 28)
  }
}

// MARK: - Public view

extension OcaLevelSensor {
  var value: OcaBoundedPropertyValue<OcaDB> {
    if case let .success(readingValue) = reading {
      readingValue
    } else {
      OcaBoundedPropertyValue(value: -144.0, in: -144.0...0.0)
    }
  }
}

public struct OcaLevelSensorView: OcaView {
  @State
  var object: OcaLevelSensor
  @StateObject
  private var ballistics = PPMBallistics()

  public init(_ object: OcaRoot) {
    _object = State(wrappedValue: object as! OcaLevelSensor)
  }

  public var body: some View {
    HStack(spacing: 2) {
      LevelMeterScale(minDB: object.value.minValue, maxDB: object.value.maxValue)
      LevelMeterBar(
        dB: ballistics.displayDB,
        minDB: object.value.minValue,
        maxDB: object.value.maxValue
      )
    }
    .frame(minHeight: 200)
    .task {
      await object.$reading.subscribe(object)
      ballistics.start()
      do {
        for try await result in object.$reading.async {
          if case let .success(value) = result,
             let bounded = value as? OcaBoundedPropertyValue<OcaDB>
          {
            ballistics.update(dB: bounded.value)
          }
        }
      } catch {}
      ballistics.stop()
    }
  }
}
