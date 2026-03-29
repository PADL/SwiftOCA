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

public protocol OcaViewRepresentable: OcaRoot {
  var viewType: any OcaView.Type { get }
}

extension Array where Element: OcaRoot {
  var allMembersAreViewRepresentable: Bool {
    allSatisfy { $0 is OcaViewRepresentable }
  }
}

// MARK: - OcaViewRepresentable conformances

// Declared here to ensure the conformance metadata is linked into the
// same compilation unit as the runtime `is`/`as?` checks.

extension OcaBooleanActuator: OcaViewRepresentable {
  public var viewType: any OcaView.Type { OcaBooleanView.self }
}

extension OcaFloat32Actuator: OcaViewRepresentable {
  public var viewType: any OcaView.Type { OcaFloat32ActuatorView.self }
}

extension OcaGain: OcaViewRepresentable {
  public var viewType: any OcaView.Type { OcaGainView.self }
}

extension OcaMute: OcaViewRepresentable {
  public var viewType: any OcaView.Type { OcaMuteView.self }
}

extension OcaPanBalance: OcaViewRepresentable {
  public var viewType: any OcaView.Type { OcaPanBalanceView.self }
}

extension OcaPolarity: OcaViewRepresentable {
  public var viewType: any OcaView.Type { OcaPolarityView.self }
}

extension OcaGenericBasicSensor: OcaViewRepresentable {
  public var viewType: any OcaView.Type { OcaGenericBasicSensorView<T>.self }
}

extension OcaBooleanSensor: OcaViewRepresentable {
  public var viewType: any OcaView.Type { OcaBooleanSensorView.self }
}

extension OcaLevelSensor: OcaViewRepresentable {
  public var viewType: any OcaView.Type { OcaLevelSensorView.self }
}

extension OcaIdentificationSensor: OcaViewRepresentable {
  public var viewType: any OcaView.Type { OcaIdentificationSensorView.self }
}

public struct OcaDetailView: OcaView {
  let connection: Ocp1Connection?
  let objectIdentification: OcaObjectIdentification?

  @Environment(\.lastError)
  var lastError
  @State
  var object: OcaRoot? = nil

  public init(
    _ connection: Ocp1Connection,
    objectIdentification: OcaObjectIdentification
  ) {
    self.connection = connection
    self.objectIdentification = objectIdentification
  }

  public init(_ object: SwiftOCA.OcaRoot) {
    connection = nil
    objectIdentification = nil
    _object = State(wrappedValue: object)
  }

  @ViewBuilder
  static func contentView(_ object: OcaRoot) -> some View {
    if object is OcaMatrix {
      OcaMatrixNavigationSplitView(object)
    } else if let viewRepresentable = object as? OcaViewRepresentable {
      AnyView(erasing: viewRepresentable.viewType.init(object))
    } else {
      OcaPropertyTableView(object)
    }
  }

  public var body: some View {
    Group {
      if let object {
        Self.contentView(object)
          .refreshableToInitialState(object)
      } else {
        ProgressView()
      }
    }
    .task {
      if object == nil, let connection, let objectIdentification {
        object = try? await connection.resolve(object: objectIdentification)
      }
    }
  }
}
