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

@OcaConnection
public class OcaClassRegistry {
  public static let shared = try! OcaClassRegistry()

  /// Mapping of classID to class name
  private var classIDMap = [OcaClassIdentification: OcaRoot.Type]()

  public func register<T: OcaRoot>(
    classID: OcaClassID = T.classID,
    classVersion: OcaClassVersionNumber = T.classVersion,
    _ type: T.Type
  ) throws {
    let classIdentification = OcaClassIdentification(
      classID: classID,
      classVersion: classVersion
    )

    if classIDMap.keys.contains(classIdentification) {
      throw Ocp1Error.status(.parameterError)
    }

    classIDMap[classIdentification] = type.self
  }

  private func match(classIdentification: OcaClassIdentification) -> OcaClassIdentification? {
    var classID: OcaClassID? = classIdentification.classID

    repeat {
      var classVersion = OcaRoot.classVersion

      repeat {
        // FIXME: why are we even looking up by class version?
        let id = OcaClassIdentification(classID: classID!, classVersion: classVersion)

        if classIDMap.keys.contains(id) {
          return id
        }

        classVersion = classVersion - 1
      } while classVersion != 0

      classID = classID?.parent
    } while classID != nil

    return nil
  }

  private func match<T: OcaRoot>(classIdentification: OcaClassIdentification) throws -> T.Type {
    guard let classIdentification = match(classIdentification: classIdentification)
    else { throw Ocp1Error.objectClassMismatch }
    guard let type = classIDMap[classIdentification] as? T.Type
    else { throw Ocp1Error.noMatchingTypeForClass }

    return type
  }

  func assign<T: OcaRoot>(
    classIdentification: OcaClassIdentification,
    objectNumber: OcaONo
  ) throws -> T {
    let type: T.Type = try match(classIdentification: classIdentification)
    return type.init(objectNumber: objectNumber)
  }

  init() throws {
    // try register built-in classes
    try register(OcaRoot.self)

    // agents
    try register(OcaAgent.self)
    try register(OcaEventHandler.self)
    try register(OcaPhysicalPosition.self)
    try register(OcaTimeSource.self)
    try register(OcaMediaClock3.self)
    try register(OcaGrouper.self)
    try register(OcaGroup.self)
    try register(OcaCounterNotifier.self)
    try register(OcaCounterSetAgent.self)

    // managers
    try register(OcaManager.self)
    try register(OcaDeviceManager.self)
    // try register(OcaLibraryManager.self)
    try register(OcaNetworkManager.self)
    try register(OcaSubscriptionManager.self)
    try register(OcaLockManager.self)
    try register(OcaDiagnosticManager.self)
    try register(OcaAudioProcessingManager.self)
    try register(OcaDeviceTimeManager.self)
    try register(OcaMediaClockManager.self)

    // workers
    try register(OcaWorker.self)
    try register(OcaBlock.self)
    try register(OcaMatrix.self)

    // actuators
    try register(OcaActuator.self)
    try register(OcaBasicActuator.self)
    try register(OcaBooleanActuator.self)
    try register(OcaUint8Actuator.self)
    try register(OcaUint16Actuator.self)
    try register(OcaUint32Actuator.self)
    try register(OcaInt8Actuator.self)
    try register(OcaInt16Actuator.self)
    try register(OcaInt32Actuator.self)
    try register(OcaFloat32Actuator.self)
    try register(OcaFloat64Actuator.self)
    try register(OcaStringActuator.self)
    // TODO: Bitstring support
    // try register(OcaBitstringActuator.self)

    try register(OcaGain.self)
    try register(OcaMute.self)
    try register(OcaPanBalance.self)
    try register(OcaPolarity.self)
    try register(OcaSwitch.self)

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
    try register(OcaIdentificationSensor.self)

    // application networks
    try register(OcaControlNetwork.self)
    try register(OcaApplicationNetwork.self)
    try register(OcaMediaTransportNetwork.self)

    // networks
    try register(OcaNetworkApplication.self)
    try register(OcaMediaTransportApplication.self)
    try register(OcaNetworkInterface.self)
  }
}
