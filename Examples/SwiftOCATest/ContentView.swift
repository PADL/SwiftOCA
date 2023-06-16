//
//  ContentView.swift
//  OCALiteSwiftUIController
//
//  Created by Luke Howard on 27/5/2023.
//

import SwiftUI
import SwiftOCA
import SwiftOCAUI
import Socket

struct ContentView: View {
    @StateObject var connection: AES70OCP1Connection

    let id = OcaObjectIdentification(oNo: 0x9008, classIdentification: OcaMute.classIdentification)

    init() {
        let connection = AES70OCP1TCPConnection(deviceAddress: IPv4SocketAddress(address: IPv4Address(rawValue: "127.0.0.1")!, port: 65000))
        self._connection = StateObject<AES70OCP1Connection>(wrappedValue: connection)
    }

    var body: some View {
        HStack {
            Text("Mute")
            Spacer()
            
            OcaMuteView(connection, object: id)
        }
        .padding()
        .task {
            do {
                try await self.connection.connect()
            } catch(let error) {
                print("Connection error: \(error)")
            }
        }
    }
}
