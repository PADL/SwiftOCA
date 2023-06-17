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
    @EnvironmentObject var connection: AES70OCP1Connection
    let id = OcaObjectIdentification(oNo: 0x9008, classIdentification: OcaMute.classIdentification)

    var body: some View {
        HStack {
            OcaRootBlockView(connection)
        }
        .padding()
    }
}
