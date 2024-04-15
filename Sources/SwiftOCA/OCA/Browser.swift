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

#if canImport(Darwin)

import AsyncAlgorithms
import Foundation

extension NetService: @unchecked
Sendable {}

public class OcaBrowser: NSObject, NetServiceBrowserDelegate, @unchecked
Sendable {
    public enum ServiceType: String, Sendable {
        case tcp = "_oca._tcp."
        case tcpSecure = "_ocasec._tcp."
        case udp = "_oca._udp."
        case tcpWebSocket = "_ocaws._tcp."
    }

    public enum Result {
        case didNotSearch(Error)
        case didFind(NetService)
        case didRemove(NetService)
    }

    private let browser: NetServiceBrowser
    public let channel: AsyncChannel<Result>

    public init(serviceType: ServiceType) {
        browser = NetServiceBrowser()
        channel = AsyncChannel<Result>()
        super.init()
        browser.delegate = self

        Task {
            self.browser.searchForServices(ofType: serviceType.rawValue, inDomain: "local.")
        }
    }

    deinit {
        browser.stop()
    }

    public func netServiceBrowserWillSearch(_ browser: NetServiceBrowser) {}

    private func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch error: Error) {
        Task {
            await channel.send(Result.didNotSearch(error))
        }
    }

    public func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didFind service: NetService,
        moreComing: Bool
    ) {
        Task {
            await channel.send(Result.didFind(service))
        }
    }

    public func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didRemove service: NetService,
        moreComing: Bool
    ) {
        Task {
            await channel.send(Result.didRemove(service))
        }
    }

    public func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        channel.finish()
    }
}

fileprivate final class OcaResolverDelegate: NSObject, NetServiceDelegate, Sendable {
    typealias ResolutionResult = Result<Data, Error>
    let channel: AsyncChannel<ResolutionResult>

    init(_ channel: AsyncChannel<ResolutionResult>) {
        self.channel = channel
    }

    deinit {
        channel.finish()
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        Task {
            guard let addresses = sender.addresses, !addresses.isEmpty else {
                await channel.send(.failure(Ocp1Error.serviceResolutionFailed))
                return
            }

            for address in addresses {
                await channel.send(ResolutionResult.success(address))
            }
        }
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        let errorCode = errorDict[NetService.errorCode]!.intValue
        let errorDomain = errorDict[NetService.errorDomain]!.stringValue

        Task {
            await channel.send(.failure(NSError(domain: errorDomain, code: errorCode)))
        }
    }
}

fileprivate protocol Ocp1ConnectionFactory {}

extension Ocp1ConnectionFactory {
    init(reassigningSelfTo other: Self) async {
        self = other
    }
}

extension Ocp1Connection: Ocp1ConnectionFactory {
    public convenience init(_ netService: NetService) async throws {
        guard let serviceType = OcaBrowser.ServiceType(rawValue: netService.type) else {
            throw Ocp1Error.unknownServiceType
        }

        let channel = AsyncChannel<OcaResolverDelegate.ResolutionResult>()
        let delegate = OcaResolverDelegate(channel)
        netService.delegate = delegate
        netService.schedule(in: RunLoop.main, forMode: .default)
        netService.resolve(withTimeout: 5)

        for await result in channel {
            switch result {
            case let .success(address):
                // FIXME: support IPv6
                guard address.withUnsafeBytes({ unbound -> Bool in
                    unbound.withMemoryRebound(to: sockaddr.self) { cSockAddr -> Bool in
                        cSockAddr.baseAddress!.pointee.sa_family == AF_INET
                    }
                }) == true else {
                    continue
                }
                channel.finish()

                switch serviceType {
                case .tcp:
                    await self
                        .init(
                            reassigningSelfTo: try Ocp1TCPConnection(
                                deviceAddress: address
                            ) as! Self
                        )
                    return
                case .udp:
                    await self
                        .init(
                            reassigningSelfTo: try Ocp1UDPConnection(
                                deviceAddress: address
                            ) as! Self
                        )
                    return
                default:
                    throw Ocp1Error.unknownServiceType
                }
            case let .failure(error):
                throw error
            }
        }

        throw Ocp1Error.serviceResolutionFailed
    }
}

#endif
