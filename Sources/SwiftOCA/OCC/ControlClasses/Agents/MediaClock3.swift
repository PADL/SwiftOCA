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

open class OcaMediaClock3: OcaAgent {
    override public class var classID: OcaClassID { OcaClassID("1.2.15") }
    override public class var classVersion: OcaClassVersionNumber { 3 }

    @OcaProperty(
        propertyID: OcaPropertyID("3.1"),
        getMethodID: OcaMethodID("3.1"),
        setMethodID: OcaMethodID("3.2")
    )
    public var availability: OcaProperty<OcaMediaClockAvailability>.PropertyValue

    @OcaProperty(
        propertyID: OcaPropertyID("3.2")
    )
    public var timeSourceONo: OcaProperty<OcaONo>.PropertyValue

    @OcaProperty(
        propertyID: OcaPropertyID("3.3"),
        getMethodID: OcaMethodID("3.5"),
        setMethodID: OcaMethodID("3.6")
    )
    public var offset: OcaProperty<OcaTime>.PropertyValue

    @OcaProperty(
        propertyID: OcaPropertyID("3.4"),
        getMethodID: OcaMethodID("3.3"),
        setMethodID: OcaMethodID("3.4")
    )
    public var currentRate: OcaProperty<OcaMediaClockRate>.PropertyValue

    @OcaProperty(
        propertyID: OcaPropertyID("3.5"),
        getMethodID: OcaMethodID("3.7")
    )
    public var supportedRates: OcaProperty<[OcaONo: [OcaMediaClockRate]]>.PropertyValue
}
