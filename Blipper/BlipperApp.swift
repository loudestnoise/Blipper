//
//  BlipperApp.swift
//  Blipper
//
//  Created by David Cintron on 10/27/26.
//

import SwiftUI

@main
struct BlipperApp: App {
    @State private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            if Self.useMockData {
                MainTabView(initialTab: Self.initialTab)
            } else if let provider = session.provider {
                MainTabView(
                    glucoseProvider: provider,
                    therapyProvider: provider,
                    deviceProvider: provider,
                    shareProvider: provider,
                    email: session.email,
                    onSignOut: session.signOut,
                    initialTab: Self.initialTab
                )
                .id(session.email)
            } else {
                LoginView(session: session)
            }
        }
    }

    // MARK: Debug launch arguments

    /// `-useMockData` skips login and runs on the mock providers (Debug builds only).
    private static var useMockData: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-useMockData")
        #else
        false
        #endif
    }

    /// `-initialTab today|trends|log|settings` picks the starting tab (Debug builds only).
    private static var initialTab: MainTabView.Tab {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-initialTab"), args.indices.contains(index + 1),
           let tab = MainTabView.Tab(rawValue: args[index + 1]) {
            return tab
        }
        #endif
        return .today
    }
}
