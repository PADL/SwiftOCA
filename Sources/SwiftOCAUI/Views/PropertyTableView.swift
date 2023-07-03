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

struct Property: Identifiable {
    typealias ID = Int

    var name: String
    var keyPath: PartialKeyPath<OcaRoot>
    var value: any OcaPropertyRepresentable

    var id: ID {
        value.propertyIDs.hashValue
    }

    var idString: String {
        // FIXME: breakout vector properties
        value.propertyIDs.map { String(describing: $0) }.joined(separator: ", ")
    }
}

extension OcaPropertyRepresentable {
    var headingText: Text {
        Text(description)
    }
}

struct OcaPropertyTableView: OcaView {
    @StateObject
    var object: OcaRoot

    init(_ object: OcaRoot) {
        _object = StateObject(wrappedValue: object)
    }

    public var body: some View {
        VStack {
            Text(object.navigationLabel).font(.title).padding()
            Table(of: Property.self) {
                TableColumn("Name", value: \.name)
                TableColumn("ID", value: \.idString)
                TableColumn("Value") {
                    if $0.value.isLoading {
                        ProgressView()
                    } else {
                        Text($0.value.description)
                    }
                }
            } rows: {
                let allPropertyKeyPaths: [Property] = object.allPropertyKeyPaths.map {
                    propertyName, propertyKeyPath in
                    Property(
                        name: propertyName,
                        keyPath: propertyKeyPath,
                        value: object[keyPath: propertyKeyPath] as! any OcaPropertyRepresentable
                    )
                }.sorted {
                    $0.value.propertyIDs[0] < $1.value.propertyIDs[0]
                }
                ForEach(allPropertyKeyPaths) { property in
                    TableRow(property)
                }
            }.task {
                for property in object.allPropertyKeyPaths {
                    await (object[keyPath: property.value] as! any OcaPropertyRepresentable)
                        .subscribe(object)
                }
            }
        }
    }
}
