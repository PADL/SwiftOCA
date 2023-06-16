//
//  ContentView.swift
//  OCALiteSwiftUIController
//
//  Created by Luke Howard on 27/5/2023.
//

import SwiftUI
import SwiftOCA
import SwiftOCAUI

struct ContentView: View {
    var connection: AES70OCP1Connection
    let id = OcaObjectIdentification(oNo: 0x9008, classIdentification: OcaMute.classIdentification)

    init(_ connection: AES70OCP1Connection) {
        self.connection = connection
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
