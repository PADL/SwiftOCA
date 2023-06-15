//
//  ContentView.swift
//  OCALiteSwiftUIController
//
//  Created by Luke Howard on 27/5/2023.
//

import SwiftUI
import SwiftOCA
import Socket

struct ContentView: View {
    @StateObject var connection: AES70OCP1Connection
    @StateObject var muteObject: OcaMute

    init() {
        let id = OcaObjectIdentification(oNo: 0x9008, classIdentification: OcaMute.classIdentification)
        let connection = AES70OCP1SocketConnection(deviceAddress: IPv4SocketAddress(address: IPv4Address(rawValue: "127.0.0.1")!, port: 65000))
        self._connection = StateObject<AES70OCP1Connection>(wrappedValue: connection)
        self._muteObject = StateObject(wrappedValue: connection.resolve(object: id) as! OcaMute)
    }

    var body: some View {
        HStack {
            Text("Mute")
            Spacer()
            ZStack {
                if muteObject.state == .initial || muteObject.state == .requesting {
                    ProgressView()
                } else {
                    Toggle(isOn: .init(get: {
                        if case let .success(muteState) = muteObject.state {
                            return muteState == .muted
                        } else {
                            return false
                        }
                    }, set: { isOn in
                        debugPrint("---> Setting mute state to \(isOn)")
                        muteObject.state = .success(isOn ? .muted : .unmuted)
                    })) {
                    }
                }
            }
        }
        .padding()
        .task {
            do {
                try await self.connection.connect()
            } catch(let error) {
                print("Connection error: \(error)")
            }
        }
        .onReceive(self.muteObject.$state) { value in
        }
    }
}
