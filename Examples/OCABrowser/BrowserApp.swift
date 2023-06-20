//
//  SwiftOCATestApp.swift
//  SwiftOCATest
//
//  Created by Luke Howard on 15/6/2023.
//

import SwiftUI
import SwiftOCA
import Socket

@main
struct SwiftOCATestApp: App {
    
    @StateObject var connection: AES70OCP1Connection
    @Environment(\.refresh) private var refresh
    
    init() {
        let connection = AES70OCP1UDPConnection(deviceAddress: IPv4SocketAddress(address: IPv4Address(rawValue: "127.0.0.1")!, port: 65000))
        self._connection = StateObject<AES70OCP1Connection>(wrappedValue: connection)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    do {
                        try await self.connection.connect()
                    } catch(let error) {
                        print("Connection error: \(error)")
                    }
                }
                .environmentObject(connection)
        }
        .commands {
            CommandGroup(replacing: .toolbar) {
                Button("Refresh") {
                    Task {
                        await refresh?()
                    }
                }.keyboardShortcut("R")
            }
        }
    }
}
