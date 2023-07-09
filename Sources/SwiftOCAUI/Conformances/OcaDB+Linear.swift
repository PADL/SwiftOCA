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

func OcaDBToGain(dB: OcaDB, in range: ClosedRange<OcaDB>) -> OcaFloat32 {
    let gain: OcaFloat32

    precondition(range.upperBound > 0)

    if dB == range.lowerBound {
        gain = 0.0
    } else {
        gain = powf(10.0, dB / range.upperBound)
    }

    return gain
}

func OcaGainToDB(gain: OcaFloat32, in range: ClosedRange<OcaDB>, step: OcaDB? = nil) -> OcaDB {
    var dB: OcaFloat32

    if gain == 0.0 {
        dB = range.lowerBound
    } else {
        dB = log10(gain) * range.upperBound
        if dB < range.lowerBound {
            dB = range.lowerBound
        }
    }

    if let step {
        dB = round(dB / step) * step
    }

    return dB
}
