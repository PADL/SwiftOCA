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

import SwiftUI
import SwiftOCA

func OcaDBToGain(dB: OcaDB, minGain: OcaDB, maxGain: OcaDB) -> OcaFloat32 {
    let gain: OcaFloat32
    
    precondition(maxGain > 0)
    
    if dB == minGain {
        gain = 0.0
    } else {
        gain = powf(10.0, dB / maxGain)
    }
    
    return gain
}

func OcaGainToDB(gain: OcaFloat32, minGain: OcaDB, maxGain: OcaDB, step: OcaDB? = nil) -> OcaDB {
    var dB: OcaFloat32
    
    if gain == 0.0 {
        dB = minGain
    } else {
        dB = log10(gain) * maxGain
        if (dB < minGain) {
            dB = minGain
        }
    }
    
    if let step {
        dB = round(dB / step) * step
    }
    
    return dB
}
