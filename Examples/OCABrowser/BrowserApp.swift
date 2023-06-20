//
//  SwiftOCATestApp.swift
//  SwiftOCATest
//
//  Created by Luke Howard on 15/6/2023.
//

import SwiftUI
import SwiftOCAUI

@main
struct SwiftOCATestApp: App {
    
    @Environment(\.refresh) private var refresh
    
    var body: some Scene {
        WindowGroup {
            OcaBonjourDiscoveryView()
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
