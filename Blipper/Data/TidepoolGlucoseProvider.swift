//
//  TidepoolGlucoseProvider.swift
//  Blipper
//

import Foundation

/// Fetches CGM readings and device info from Tidepool, logging in lazily and once more if the session expires.
actor TidepoolGlucoseProvider: GlucoseDataProvider, DeviceInfoProvider, TherapyDataProvider {
    /// How far back to look for device uploads and settings.
    private static let deviceLookback: TimeInterval = 30 * 86_400

    private let client: TidepoolClient
    private let credentials: TidepoolCredentials
    private var session: TidepoolSession?

    init(credentials: TidepoolCredentials, client: TidepoolClient = TidepoolClient()) {
        self.credentials = credentials
        self.client = client
    }

    func readings(in interval: DateInterval) async throws -> [GlucoseReading] {
        try await withSession { session in
            try await client.cgmReadings(session: session, in: interval)
        }
    }

    func therapy(in interval: DateInterval) async throws -> TherapyData {
        try await withSession { session in
            try await client.therapy(session: session, in: interval)
        }
    }

    func fingersticks(in interval: DateInterval) async throws -> [BGMReading] {
        try await withSession { session in
            try await client.fingersticks(session: session, in: interval)
        }
    }

    func devices() async throws -> [DeviceInfo] {
        try await withSession { session in
            try await client.devices(session: session, since: Date().addingTimeInterval(-Self.deviceLookback))
        }
    }

    /// Runs `operation` with a valid session, logging in again and retrying once if the token was rejected.
    private func withSession<T: Sendable>(_ operation: (TidepoolSession) async throws -> T) async throws -> T {
        let session = try await currentSession()
        do {
            return try await operation(session)
        } catch TidepoolError.invalidCredentials {
            self.session = nil
            let fresh = try await currentSession()
            return try await operation(fresh)
        }
    }

    private func currentSession() async throws -> TidepoolSession {
        if let session { return session }
        let fresh = try await client.login(email: credentials.email, password: credentials.password)
        session = fresh
        return fresh
    }
}
