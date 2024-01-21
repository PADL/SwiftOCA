//
// Copyright (c) 2024 PADL Software Pty Ltd
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

open class OcaTaskManager: OcaManager {
    override public class var classID: OcaClassID { OcaClassID("1.3.11") }
    override public class var classVersion: OcaClassVersionNumber { 3 }

    @OcaProperty(
        propertyID: OcaPropertyID("3.1"),
        getMethodID: OcaMethodID("3.5")
    )
    public var state: OcaProperty<OcaTaskManagerState>.PropertyValue

    @OcaProperty(
        propertyID: OcaPropertyID("3.2"),
        getMethodID: OcaMethodID("3.9")
    )
    public var tasks: OcaProperty<[OcaTaskID: OcaTask]>.PropertyValue

    // 3.1 Enable
    // 3.2 ControlAllTasks
    // 3.3 ControlTaskGroup
    // 3.4 ControlTask
    // 3.7 GetTaskStatus
    // 3.8 AddTask
    // 3.10 GetTask
    // 3.11 SetTask
    // 3.12 DeleteTask

    public convenience init() {
        self.init(objectNumber: OcaTaskManagerONo)
    }
}
