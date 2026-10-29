//
//  DataConnections.swift
//  Blipper
//
//  Cloud-to-cloud data sources as Tidepool Web presents them: the providers a user can connect,
//  the data source records Tidepool keeps for each, and the status line shown per provider.
//

import Foundation

/// A cloud data provider Tidepool can pull from. Order matches the Data Connections list in Tidepool Web.
nonisolated enum DataProvider: String, CaseIterable, Identifiable, Sendable {
    case dexcom
    case twiist
    case abbott

    var id: String { rawValue }

    /// The `providerName` Tidepool uses in data sources and OAuth paths.
    var providerName: String { rawValue }

    var displayName: String {
        switch self {
        case .dexcom: "Dexcom"
        case .abbott: "FreeStyle Libre"
        case .twiist: "twiist"
        }
    }

    /// Asset catalog image, taken from Tidepool Web's icon set.
    var logoAsset: String {
        switch self {
        case .dexcom: "DexcomLogo"
        case .abbott: "LibreLogo"
        case .twiist: "TwiistLogo"
        }
    }

    /// Tidepool Web hides the disconnect action for twiist.
    var allowsDisconnect: Bool { self != .twiist }

    /// twiist does not report import times, so no "last data" line is shown.
    var indeterminateImportTime: Bool { self == .twiist }

    /// Extra step the user must take elsewhere after disconnecting here.
    var disconnectInstructions: (title: String, message: String)? {
        switch self {
        case .abbott:
            (
                "Please disconnect in your FreeStyle Libre or LibreView application as well.",
                "Disconnecting here has stopped new data collection from your FreeStyle Libre device. To fully revoke consent for sharing data with Tidepool, log into your FreeStyle Libre or LibreView app, access the \"Connected Apps\" page, and click \"Manage\" and then \"Disconnect\" next to Tidepool."
            )
        default:
            nil
        }
    }

    /// Path the restricted token must be scoped to for this provider's authorization.
    var oauthPath: String { "/v1/oauth/\(providerName)" }
}

/// One of Tidepool's data source records for the account.
nonisolated struct DataSource: Identifiable, Sendable, Equatable {
    enum State: Sendable, Equatable {
        case connected
        case disconnected
        case error
        case other(String)

        init(rawValue: String) {
            switch rawValue {
            case "connected": self = .connected
            case "disconnected": self = .disconnected
            case "error": self = .error
            default: self = .other(rawValue)
            }
        }
    }

    let id: String
    let providerName: String
    let state: State
    let createdTime: Date?
    let modifiedTime: Date?
    let lastImportTime: Date?
    let latestDataTime: Date?
}

/// A provider paired with its current data source, with the copy Tidepool Web shows for that state.
nonisolated struct DataConnection: Identifiable, Sendable, Equatable {
    enum Status: Sendable {
        case notConnected, connected, disconnected, error
    }

    enum Action: Sendable {
        case connect, reconnect, disconnect
    }

    let provider: DataProvider
    let source: DataSource?

    var id: DataProvider { provider }

    var status: Status {
        switch source?.state {
        case .connected: .connected
        case .error: .error
        case .disconnected: .disconnected
        case .other, .none: .notConnected
        }
    }

    var statusText: String {
        switch status {
        case .notConnected: "Not connected"
        case .connected: "Connected"
        case .disconnected: "Disconnected"
        case .error: "Error Connecting"
        }
    }

    /// Secondary line under the status, relative to `now`.
    func message(now: Date = Date()) -> String? {
        guard let source else { return nil }
        switch status {
        case .connected:
            if provider.indeterminateImportTime { return nil }
            guard let lastImport = source.lastImportTime else {
                return "Awaiting data, this can take a few minutes"
            }
            guard let latest = source.latestDataTime else {
                return "No data found as of \(Self.ago(lastImport, now: now))"
            }
            return "Last data \(Self.ago(latest, now: now))"
        case .error:
            let when = source.modifiedTime ?? source.lastImportTime ?? source.createdTime
            let update = when.map { "Last update \(Self.ago($0, now: now)). " } ?? ""
            return update + "Please reconnect your account to keep syncing data."
        case .disconnected, .notConnected:
            return nil
        }
    }

    /// Actions offered for this state, in display order.
    var actions: [Action] {
        switch status {
        case .notConnected, .disconnected: [.connect]
        case .error: [.reconnect]
        case .connected: provider.allowsDisconnect ? [.disconnect] : []
        }
    }

    /// Picks the data source that represents a provider when Tidepool holds more than one:
    /// a connected one first, then one in error, then the most recently changed.
    static func current(for provider: DataProvider, in sources: [DataSource]) -> DataSource? {
        let matching = sources.filter { $0.providerName == provider.providerName }
        func rank(_ source: DataSource) -> Int {
            switch source.state {
            case .connected: 0
            case .error: 1
            case .disconnected: 2
            case .other: 3
            }
        }
        return matching.min {
            let (a, b) = (rank($0), rank($1))
            if a != b { return a < b }
            return ($0.modifiedTime ?? .distantPast) > ($1.modifiedTime ?? .distantPast)
        }
    }

    private static func ago(_ date: Date, now: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
