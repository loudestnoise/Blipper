//
//  DataConnectionProvider.swift
//  Blipper
//

import Foundation

/// Source of cloud-to-cloud connection state and the two actions a user can take on it.
nonisolated protocol DataConnectionProvider: Sendable {
    /// Tidepool's data source records for the account.
    func dataSources() async throws -> [DataSource]
    /// Mints a short-lived restricted token and returns the URL that starts the provider's sign-in.
    /// The sign-in itself runs in a browser; Tidepool finishes it on its own pages.
    func authorizationURL(for provider: DataProvider) async throws -> URL
    /// Revokes Tidepool's authorization with the provider.
    func disconnect(_ provider: DataProvider) async throws
}

/// In-memory connection state so the Data Connections screen works under `-useMockData`.
actor MockDataConnectionProvider: DataConnectionProvider {
    private var sources: [DataSource]

    init() {
        let now = Date()
        sources = [
            DataSource(
                id: "mock-dexcom",
                providerName: DataProvider.dexcom.providerName,
                state: .connected,
                createdTime: now.addingTimeInterval(-30 * 86_400),
                modifiedTime: now.addingTimeInterval(-10 * 60),
                lastImportTime: now.addingTimeInterval(-10 * 60),
                latestDataTime: now.addingTimeInterval(-15 * 60)
            ),
            DataSource(
                id: "mock-abbott",
                providerName: DataProvider.abbott.providerName,
                state: .error,
                createdTime: now.addingTimeInterval(-60 * 86_400),
                modifiedTime: now.addingTimeInterval(-3 * 86_400),
                lastImportTime: now.addingTimeInterval(-3 * 86_400),
                latestDataTime: now.addingTimeInterval(-3 * 86_400)
            ),
        ]
    }

    func dataSources() async throws -> [DataSource] {
        try await Task.sleep(for: .milliseconds(200))
        return sources
    }

    func authorizationURL(for provider: DataProvider) async throws -> URL {
        try await Task.sleep(for: .milliseconds(300))
        return URL(string: "https://www.tidepool.org/")!
    }

    func disconnect(_ provider: DataProvider) async throws {
        try await Task.sleep(for: .milliseconds(300))
        sources = sources.map { source in
            guard source.providerName == provider.providerName else { return source }
            return DataSource(
                id: source.id, providerName: source.providerName, state: .disconnected,
                createdTime: source.createdTime, modifiedTime: Date(),
                lastImportTime: source.lastImportTime, latestDataTime: source.latestDataTime
            )
        }
    }
}
