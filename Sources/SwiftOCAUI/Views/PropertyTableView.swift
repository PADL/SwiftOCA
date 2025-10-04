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

private struct Property: Identifiable {
  typealias ID = Int

  var name: String
  var keyPath: AnyKeyPath

  var id: ID {
    keyPath.hashValue
  }

  fileprivate func getValue(from object: OcaRoot) -> any OcaPropertyRepresentable {
    object[keyPath: keyPath] as! any OcaPropertyRepresentable
  }

  fileprivate func getIdString(from object: OcaRoot) -> String {
    // FIXME: breakout vector properties
    getValue(from: object).propertyIDs.map { String(describing: $0) }.joined(separator: ", ")
  }
}

private struct PropertyValueView: View {
  private let property: Property
  private let wrappedValue: any OcaPropertyRepresentable
  @State
  private var currentValue: Result<Any, Error>?

  init(property: Property, object: OcaRoot) {
    self.property = property
    wrappedValue = property.getValue(from: object)
  }

  var body: some View {
    Group {
      if let currentValue {
        switch currentValue {
        case let .success(value):
          Text("\(value)")
        case let .failure(error):
          Text("Error: \(error)").foregroundStyle(.tertiary)
        }
      } else {
        ProgressView()
      }
    }
    .task {
      do {
        for try await values in wrappedValue.async {
          currentValue = values
        }
      } catch {}
    }
  }
}

extension OcaPropertyRepresentable {
  var headingText: Text {
    Text(description)
  }
}

struct OcaPropertyTableView: OcaView {
  @State
  var object: OcaRoot

  init(_ object: OcaRoot) {
    _object = State(wrappedValue: object)
  }

  var body: some View {
    VStack {
      Text(object.navigationLabel).font(.title).padding()
      Table(of: Property.self) {
        TableColumn("Name", value: \.name)
        TableColumn("ID") { property in
          Text(property.getIdString(from: object))
        }
        TableColumn("Value") { property in
          PropertyValueView(property: property, object: object)
        }
      } rows: {
        let allProperties: [Property] = object.allPropertyKeyPathsUncached.map {
          propertyName, propertyKeyPath in
          Property(
            name: propertyName,
            keyPath: propertyKeyPath
          )
        }.sorted {
          $0.getValue(from: object).propertyIDs[0] < $1.getValue(from: object).propertyIDs[0]
        }
        ForEach(allProperties) { property in
          TableRow(property)
        }
      }.task {
        for property in await object.allPropertyKeyPaths {
          await (object[keyPath: property.value] as! any OcaPropertyRepresentable)
            .subscribe(object)
        }
      }
    }
  }
}
