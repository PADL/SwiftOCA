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

// What a class manager says of a device's classes, in OCA's terms. Each corresponds
// to an MS-05-02 descriptor (NcClassDescriptor, NcPropertyDescriptor,
// NcMethodDescriptor, NcParameterDescriptor), with OCA's IDs and names.

/// A control class: its own properties and methods, or with those of the classes it
/// derives from too where they were asked for.
public struct OcaClassDescriptor: Codable, Sendable, Equatable {
  public var classID: OcaClassID
  public var classVersion: OcaClassVersionNumber
  public var name: OcaString
  public var properties: [OcaClassPropertyDescriptor]
  public var methods: [OcaClassMethodDescriptor]

  public init(
    classID: OcaClassID,
    classVersion: OcaClassVersionNumber,
    name: OcaString,
    properties: [OcaClassPropertyDescriptor],
    methods: [OcaClassMethodDescriptor]
  ) {
    self.classID = classID
    self.classVersion = classVersion
    self.name = name
    self.properties = properties
    self.methods = methods
  }
}

/// A property, by its OCA ID and model name. It is read only where it has no setter.
public struct OcaClassPropertyDescriptor: Codable, Sendable, Equatable {
  public var propertyID: OcaPropertyID
  public var name: OcaString
  public var typeName: OcaString
  public var isReadOnly: OcaBoolean

  public init(propertyID: OcaPropertyID, name: OcaString, typeName: OcaString, isReadOnly: OcaBoolean) {
    self.propertyID = propertyID
    self.name = name
    self.typeName = typeName
    self.isReadOnly = isReadOnly
  }
}

/// A method, by its OCA ID and model name, with its parameters in order and the type of
/// its result (empty for none).
public struct OcaClassMethodDescriptor: Codable, Sendable, Equatable {
  public var methodID: OcaMethodID
  public var name: OcaString
  public var parameters: [OcaClassParameterDescriptor]
  public var resultTypeName: OcaString

  public init(
    methodID: OcaMethodID,
    name: OcaString,
    parameters: [OcaClassParameterDescriptor],
    resultTypeName: OcaString
  ) {
    self.methodID = methodID
    self.name = name
    self.parameters = parameters
    self.resultTypeName = resultTypeName
  }
}

/// A method parameter, by its OCP.2 name.
public struct OcaClassParameterDescriptor: Codable, Sendable, Equatable {
  public var name: OcaString
  public var typeName: OcaString

  public init(name: OcaString, typeName: OcaString) {
    self.name = name
    self.typeName = typeName
  }
}
