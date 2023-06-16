//
//  SwiftOCATestApp.swift
//  SwiftOCATest
//
//  Created by Luke Howard on 15/6/2023.
//

import SwiftUI
import SwiftOCA
import Socket

extension OcaRoot: Identifiable {
    public var id: OcaONo { return self.objectNumber }
}

@main
struct SwiftOCATestApp: App {
    @StateObject var connection: AES70OCP1Connection

    init() {
        let connection = AES70OCP1TCPConnection(deviceAddress: IPv4SocketAddress(address: IPv4Address(rawValue: "127.0.0.1")!, port: 65000))
        self._connection = StateObject<AES70OCP1Connection>(wrappedValue: connection)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView(connection)
                .task {
                    do {
                        try await self.connection.connect()
                    } catch(let error) {
                        print("Connection error: \(error)")
                    }
                }
        }
    }
}

