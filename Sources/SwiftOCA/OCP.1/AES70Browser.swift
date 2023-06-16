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

#if canImport(Network)
import Foundation
import Network
import AsyncAlgorithms

public actor AES70Browser {
    public enum ServiceType: String {
        case tcp = "_oca._tcp"
        case tcpSecure = "_ocasec._tcp"
        case udp = "_oca._udp"
        case tcpWebSocket = "_ocaws._tcp"
    }
    
    public typealias BrowseResultsChange = (Set<NWBrowser.Result>, Set<NWBrowser.Result.Change>)
    
    let browser: NWBrowser
    
    public let stateUpdateChannel: AsyncChannel<NWBrowser.State>
    public let browseResultsChangedChannel: AsyncChannel<BrowseResultsChange>
    
    public init(serviceType: ServiceType) async {
        self.stateUpdateChannel = AsyncChannel<NWBrowser.State>()
        self.browseResultsChangedChannel = AsyncChannel<BrowseResultsChange>()

        let descriptor = NWBrowser.Descriptor.bonjour(type: serviceType.rawValue, domain: "local")
        let params = NWParameters()
        params.allowLocalEndpointReuse = true
        params.acceptLocalOnly = true
        params.allowFastOpen = true
        
        self.browser = NWBrowser(for: descriptor, using: params)
        
        self.browser.stateUpdateHandler = { state in
            Task {
                await self.stateUpdateChannel.send(state)
            }
        }

        self.browser.browseResultsChangedHandler = { (results, changes) in
            Task {
                await self.browseResultsChangedChannel.send((results, changes))
            }
        }
        
        self.browser.start(queue: DispatchQueue.global(qos: .default))
    }
    
    deinit {
        self.stateUpdateChannel.finish()
        self.browseResultsChangedChannel.finish()
        self.browser.cancel()
    }
}
#endif
