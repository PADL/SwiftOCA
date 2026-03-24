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

import SwiftOCA

@OcaDevice
public class OcaDeviceClassRegistry {
  public static let shared = try! OcaDeviceClassRegistry()

  private var _classIDMap = [OcaClassIdentification: OcaRoot.Type]()

  public func register<T: OcaRoot>(
    classID: OcaClassID = T.classID,
    classVersion: OcaClassVersionNumber = T.classVersion,
    _ type: T.Type
  ) throws {
    let classIdentification = OcaClassIdentification(
      classID: classID,
      classVersion: classVersion
    )

    if _classIDMap.keys.contains(classIdentification) {
      throw Ocp1Error.status(.parameterError)
    }

    _classIDMap[classIdentification] = type.self
  }

  private func _match(classIdentification: OcaClassIdentification) -> OcaClassIdentification? {
    var classID: OcaClassID? = classIdentification.classID

    repeat {
      var classVersion = OcaRoot.classVersion

      repeat {
        let id = OcaClassIdentification(classID: classID!, classVersion: classVersion)

        if _classIDMap.keys.contains(id) {
          return id
        }

        classVersion = classVersion - 1
      } while classVersion != 0

      classID = classID?.parent
    } while classID != nil

    return nil
  }

  public func match<T: OcaRoot>(
    classIdentification: OcaClassIdentification
  ) throws -> T.Type {
    guard let classIdentification = _match(classIdentification: classIdentification)
    else { throw Ocp1Error.objectClassMismatch }
    guard let type = _classIDMap[classIdentification] as? T.Type
    else { throw Ocp1Error.noMatchingTypeForClass }

    return type
  }

  public func match(classID: OcaClassID) throws -> OcaRoot.Type {
    let classIdentification = OcaClassIdentification(
      classID: classID,
      classVersion: OcaRoot.classVersion
    )
    guard let matched = _match(classIdentification: classIdentification)
    else { throw Ocp1Error.objectClassMismatch }
    guard let type = _classIDMap[matched]
    else { throw Ocp1Error.noMatchingTypeForClass }

    return type
  }

  init() throws {
    try register(OcaRoot.self)

    // agents
    try register(OcaAgent.self)
    try register(OcaMediaClock3.self)
    try register(OcaGroup.self)
    try register(OcaCounterNotifier.self)
    try register(OcaCounterSetAgent.self)
    try register(OcaTimeSource.self)

    // managers
    try register(OcaManager.self)
    try register(OcaDeviceManager.self)
    try register(OcaFirmwareManager.self)
    try register(OcaSubscriptionManager.self)
    try register(OcaNetworkManager.self)
    try register(OcaMediaClockManager.self)
    try register(OcaAudioProcessingManager.self)
    try register(OcaDeviceTimeManager.self)
    try register(OcaCodingManager.self)
    try register(OcaDiagnosticManager.self)
    try register(OcaLockManager.self)

    // workers
    try register(OcaWorker.self)
    try register(OcaBlock<OcaRoot>.self)
    try register(OcaMatrix<OcaWorker>.self)

    // actuators
    try register(OcaActuator.self)
    try register(OcaBasicActuator.self)
    try register(OcaBooleanActuator.self)
    try register(OcaInt8Actuator.self)
    try register(OcaInt16Actuator.self)
    try register(OcaInt32Actuator.self)
    try register(OcaInt64Actuator.self)
    try register(OcaUint8Actuator.self)
    try register(OcaUint16Actuator.self)
    try register(OcaUint32Actuator.self)
    try register(OcaUint64Actuator.self)
    try register(OcaFloat32Actuator.self)
    try register(OcaFloat64Actuator.self)
    try register(OcaStringActuator.self)
    try register(OcaIdentificationActuator.self)
    try register(OcaGain.self)
    try register(OcaMute.self)
    try register(OcaPanBalance.self)
    try register(OcaPolarity.self)
    try register(OcaSwitch.self)
    try register(OcaFrequencyActuator.self)
    try register(OcaSignalInput.self)
    try register(OcaSignalOutput.self)
    try register(OcaSummingPoint.self)

    // sensors
    try register(OcaSensor.self)
    try register(OcaBasicSensor.self)
    try register(OcaBooleanSensor.self)
    try register(OcaInt8Sensor.self)
    try register(OcaInt16Sensor.self)
    try register(OcaInt32Sensor.self)
    try register(OcaInt64Sensor.self)
    try register(OcaUint8Sensor.self)
    try register(OcaUint16Sensor.self)
    try register(OcaUint32Sensor.self)
    try register(OcaUint64Sensor.self)
    try register(OcaFloat32Sensor.self)
    try register(OcaFloat64Sensor.self)
    try register(OcaStringSensor.self)
    try register(OcaLevelSensor.self)
    try register(OcaAudioLevelSensor.self)
    try register(OcaIdentificationSensor.self)
    try register(OcaTemperatureSensor.self)

    // application networks
    try register(OcaApplicationNetwork.self)
    try register(OcaControlNetwork.self)
    try register(OcaMediaTransportNetwork.self)

    // datasets
    try register(OcaDataset.self)
  }
}
