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

public typealias OcaDBFS = OcaDB
public typealias OcaDBr = OcaDB
public typealias OcaDBu = OcaDB
public typealias OcaDBV = OcaDB
public typealias OcaDBz = OcaDB

public typealias OcaVoltage = OcaFloat32
public typealias OcaCurrent = OcaFloat32

public struct OcaImpedance: Codable, Sendable {
    let magnitude: OcaFloat32
    let phsae: OcaFloat32
}

public enum OcaDelayUnit: OcaUint8, Codable, Sendable {
    case time = 1
    case distance = 2
    case samples = 3
    case microseconds = 4
    case milliseconds = 5
    case centimeters = 6
    case inches = 7
    case feet = 8
}

public struct OcaDelayValue: Codable, Sendable {
    let delayValue: OcaFloat32
    let delayUnit: OcaDelayUnit
}

public typealias OcaFrequency = OcaFloat32

public typealias OcaFrequencyResponse = OcaMap<OcaFrequency, OcaDB>

public struct OcaTransferFunction: Codable, Sendable {
    var frequency: OcaList<OcaFrequency>
    var amplitude: OcaList<OcaFloat32>
    var phase: OcaList<OcaFloat32>
}

public typealias OcaPeriod = OcaUint32 // ms

public enum OcaClassicalFilterShape: OcaUint8, Codable, Sendable {
    case butterworth = 1
    case bessel = 2
    case chebyshev = 3
    case linkwitzRiley = 4
}

public enum OcaFilterPassband: OcaUint8, Codable, Sendable {
    case hiPass = 1
    case lowPass = 2
    case bandPass = 3
    case bandReject = 4
    case allPass = 5
}

public enum OcaParametricEQShape: OcaUint8, Codable, Sendable {
    case none = 0
    case peq = 1
    case lowShelv = 2
    case highShelv = 3
    case lowPass = 4
    case highPass = 5
    case bandPass = 6
    case allPass = 7
    case notch = 8
    case toneControlLowFixed = 9
    case toneControlLowSliding = 10
    case toneControlHighFixed = 11
    case toneControlHighSliding = 12
}

public enum OcaDynamicsFunction: OcaUint8, Codable, Sendable {
    case none = 0
    case compress = 1
    case limit = 2
    case expand = 3
    case gate = 4
}

public struct OcaPilotToneDetectorSpec: Codable, Sendable {
    let threshold: OcaDBr
    let frequency: OcaFrequency
    let pollInterval: OcaPeriod
}

public enum OcaWaveformType: OcaUint8, Codable, Sendable {
    case none = 0
    case dc = 1
    case sine = 2
    case square = 3
    case impulse = 4
    case noisePink = 5
    case noiseWhite = 6
    case polarityTest = 7
}

public enum OcaSweepType: OcaUint8, Codable, Sendable {
    case none = 0
    case linear = 1
    case logarithmic = 2
}

public enum OcaUnitOfMeasure: OcaUint8, Codable, Sendable {
    case none = 0
    case hertz = 1
    case degreeCelsius = 2
    case volt = 3
    case ampere = 4
    case ohm = 5
}

public enum OcaPresentationUnit: OcaUint8, Codable, Sendable {
    case dBu = 0
    case dBV = 1
    case V = 2
}

public typealias OcaTemperature = OcaFloat32

public enum OcaLevelDetectionLaw: OcaUint8, Codable, Sendable {
    case none = 0
    case rms = 1
    case peak = 2
}

public enum OcaLevelMeterLaw: OcaUint8, Codable, Sendable {
    case vu = 1
    case standardVU = 2
    case ppm1 = 3
    case ppm2 = 4
    case lkfs = 5
    case rms = 6
    case peak = 7
    case proprietaryValueBase = 128
}
