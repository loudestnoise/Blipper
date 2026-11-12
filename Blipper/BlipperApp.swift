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
            } else if !session.isSignedIn {
                LoginView(session: session)
            } else if let provider = session.provider, let account = session.account {
                MainTabView(
                    glucoseProvider: provider,
                    therapyProvider: provider,
                    deviceProvider: provider,
                    shareProvider: provider,
                    dataConnectionProvider: provider,
                    noteProvider: provider,
                    email: session.email,
                    session: session,
                    onSignOut: session.signOut,
                    initialTab: Self.initialTab
                )
                // A different account means different data everywhere: start the tabs over.
                .id(account.id)
                .task { if session.accounts.isEmpty { await session.refreshAccounts() } }
            } else {
                // Signed in, but other accounts are shared with this login and none is picked yet.
                AccountPickerView(session: session)
                    .task { if session.accounts.isEmpty { await session.refreshAccounts() } }
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

    /// `-initialTab today|trends|log|notes|settings` picks the starting tab (Debug builds only).
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
