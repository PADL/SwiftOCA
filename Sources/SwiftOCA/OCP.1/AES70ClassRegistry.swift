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

import Foundation

extension OcaClassID {
    var parent: OcaClassID? {
        if self.fieldCount == 1 {
            return nil
        }
        var fields = self.fields
        fields.removeLast()
        return OcaClassID(fields)
    }
}

public class AES70ClassRegistry {
    public static let shared = AES70ClassRegistry()

    /// Mapping of classID to class name
    private var classIDMap = [OcaClassIdentification:OcaRoot.Type]()

    @discardableResult
    public func register<T: OcaRoot>(classID: OcaClassID = T.classID,
                                     classVersion: OcaClassVersionNumber = T.classVersion,
                                     _ type: T.Type) -> OcaStatus {
        let classIdentification = OcaClassIdentification(classID: classID,
                                                         classVersion: classVersion)
        
        if classIDMap.keys.contains(classIdentification) {
            return .parameterError
        }
        
        classIDMap[classIdentification] = type.self
        return .ok
    }
    
    
    private func match(classIdentification: OcaClassIdentification) -> OcaClassIdentification? {
        var classID: OcaClassID? = classIdentification.classID
        
        // FIXME check classVersion properly
        if classIdentification.classVersion < 2 {
            return nil
        }
        
        repeat {
            let id = OcaClassIdentification(classID: classID!, classVersion: 2)
            
            if classIDMap.keys.contains(id) {
                return id
            }
            
            classID = classID?.parent
            
        } while classID != nil

        return nil
    }
    
    private func match<T: OcaRoot>(classIdentification: OcaClassIdentification) -> T.Type? {
        guard let classIdentification = match(classIdentification: classIdentification) else { return nil }
        guard let type = classIDMap[classIdentification] else { return nil }
        
        return type as? T.Type
    }
    
    func assign<T: OcaRoot>(classIdentification: OcaClassIdentification, objectNumber: OcaONo) -> T? {
        guard let type: T.Type = match(classIdentification: classIdentification) else { return nil }
        
        return type.init(objectNumber: objectNumber)
    }

    init() {
        // register built-in classes
        register(OcaRoot.self)
        
        // managers
        register(OcaManager.self)
        register(OcaSubscriptionManager.self)
        register(OcaDeviceManager.self)
        
        // workers
        register(OcaWorker.self)
        register(OcaBlock.self)
        register(OcaMatrix.self)

        //  actuators
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
        //register(OcaBitstringActuator.self)
        
        register(OcaGain.self)
        register(OcaMute.self)
        register(OcaPanBalance.self)
        register(OcaPolarity.self)
        register(OcaSwitch.self)
        
        //  sensors
        register(OcaSensor.self)
        register(OcaBasicSensor.self)
        register(OcaBooleanSensor.self)
        register(OcaLevelSensor.self)
    }

}
