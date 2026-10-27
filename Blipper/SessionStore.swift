//
//  SessionStore.swift
//  Blipper
//

import Foundation
import Observation
import OSLog

/// Holds the signed-in Tidepool account and hands out the matching data provider.
@Observable
@MainActor
final class SessionStore {
    private(set) var credentials: TidepoolCredentials? {
        didSet { provider = credentials.map { TidepoolGlucoseProvider(credentials: $0, client: client) } }
    }
    /// Data source for the current account; `nil` when signed out.
    private(set) var provider: TidepoolGlucoseProvider?
    private(set) var isSigningIn = false
    private(set) var errorMessage: String?

    private let client = TidepoolClient()

    init() {
        let saved = CredentialStore.load()
        credentials = saved
        provider = saved.map { TidepoolGlucoseProvider(credentials: $0, client: client) }
        Logger(subsystem: "com.PickleTron.Blipper", category: "session")
            .notice("session: saved credentials \(saved == nil ? "absent" : "present", privacy: .public)")
    }

    var isSignedIn: Bool { credentials != nil }
    var email: String? { credentials?.email }

    /// Verifies the login against Tidepool before storing it.
    func signIn(email: String, password: String) async {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !password.isEmpty else {
            errorMessage = "Enter your Tidepool email and password."
            return
        }
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            _ = try await client.login(email: trimmed, password: password)
            let credentials = TidepoolCredentials(email: trimmed, password: password)
            try CredentialStore.save(credentials)
            self.credentials = credentials
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        CredentialStore.clear()
        credentials = nil
        errorMessage = nil
    }
}
