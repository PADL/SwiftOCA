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
    public static let shared = OcaClassRegistry()

    /// Mapping of classID to class name
    private var classIDMap = [OcaClassIdentification: OcaRoot.Type]()

    @discardableResult
    public func register<T: OcaRoot>(
        classID: OcaClassID = T.classID,
        classVersion: OcaClassVersionNumber = T.classVersion,
        _ type: T.Type
    ) -> OcaStatus {
        let classIdentification = OcaClassIdentification(
            classID: classID,
            classVersion: classVersion
        )

        if classIDMap.keys.contains(classIdentification) {
            return .parameterError
        }

        classIDMap[classIdentification] = type.self
        return .ok
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

    init() {
        // register built-in classes
        register(OcaRoot.self)

        // agents
        register(OcaAgent.self)
        register(OcaEventHandler.self)
        register(OcaPhysicalPosition.self)
        register(OcaTimeSource.self)
        register(OcaMediaClock3.self)
        register(OcaGrouper.self)
        register(OcaGroup.self)
        register(OcaCounterNotifier.self)
        register(OcaCounterSetAgent.self)

        // managers
        register(OcaManager.self)
        register(OcaDeviceManager.self)
        // register(OcaLibraryManager.self)
        register(OcaNetworkManager.self)
        register(OcaSubscriptionManager.self)
        register(OcaLockManager.self)
        register(OcaDiagnosticManager.self)
        register(OcaNetworkManager.self)
        register(OcaAudioProcessingManager.self)
        register(OcaDeviceTimeManager.self)
        register(OcaMediaClockManager.self)

        // workers
        register(OcaWorker.self)
        register(OcaBlock.self)
        register(OcaMatrix.self)

        // actuators
        register(OcaActuator.self)
        register(OcaBasicActuator.self)
        register(OcaBooleanActuator.self)
        register(OcaUint8Actuator.self)
        register(OcaUint16Actuator.self)
        register(OcaUint32Actuator.self)
        register(OcaInt8Actuator.self)
        register(OcaInt16Actuator.self)
        register(OcaInt32Actuator.self)
        register(OcaFloat32Actuator.self)
        register(OcaFloat64Actuator.self)
        register(OcaStringActuator.self)
        // TODO: Bitstring support
        // register(OcaBitstringActuator.self)

        register(OcaGain.self)
        register(OcaMute.self)
        register(OcaPanBalance.self)
        register(OcaPolarity.self)
        register(OcaSwitch.self)

        // sensors
        register(OcaSensor.self)
        register(OcaBasicSensor.self)
        register(OcaBooleanSensor.self)
        register(OcaInt8Sensor.self)
        register(OcaInt16Sensor.self)
        register(OcaInt32Sensor.self)
        register(OcaInt64Sensor.self)
        register(OcaUint8Sensor.self)
        register(OcaUint16Sensor.self)
        register(OcaUint32Sensor.self)
        register(OcaUint64Sensor.self)
        register(OcaFloat32Sensor.self)
        register(OcaFloat64Sensor.self)
        register(OcaStringSensor.self)
        register(OcaLevelSensor.self)
        register(OcaIdentificationSensor.self)

        // application networks
        register(OcaControlNetwork.self)
        register(OcaApplicationNetwork.self)
        register(OcaMediaTransportNetwork.self)

        // networks
        register(OcaNetworkApplication.self)
        register(OcaMediaTransportApplication.self)
        register(OcaNetworkInterface.self)
    }
}
