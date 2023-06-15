//
//  SwiftOCATestApp.swift
//  SwiftOCATest
//
//  Created by Luke Howard on 15/6/2023.
//

import SwiftUI
import SwiftOCA

extension OcaRoot: Identifiable {
    public var id: OcaONo { return self.objectNumber }
}

@main
struct SwiftOCATestApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

