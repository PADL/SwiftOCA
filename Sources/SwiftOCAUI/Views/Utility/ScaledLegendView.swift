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

struct OcaScaledLegendView: View {
    var value: OcaBoundedPropertyValue<OcaDB>

    let scale: Float = 20.0

    private func y(_ value: Int) -> CGFloat {
        let dB = Float(value) * scale
        return 1.0 - CGFloat(OcaDBToFaderGain(dB: dB, in: self.value.range))
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(
                    Int(value.range.lowerBound / scale)...Int(value.range.upperBound / scale),
                    id: \.self
                ) { value in
                    Text(String(value * Int(scale)))
                        .font(.caption2)
                        .frame(maxWidth: 25, alignment: .trailing)
                        .position(x: geo.size.width * 0.5, y: geo.size.height * y(value))
                }
            }
        }
    }
}
