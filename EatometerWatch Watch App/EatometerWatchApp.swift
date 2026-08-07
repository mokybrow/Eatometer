//
//  EatometerWatchApp.swift
//  EatometerWatch Watch App
//
//  Created by Михаил Панин on 20.04.2026.
//

import SwiftUI

@main
struct EatometerWatch_Watch_AppApp: App {
    @StateObject private var sessionManager = WatchSessionManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(sessionManager)
                .task {
                    sessionManager.activate()
                }
        }
    }
}
