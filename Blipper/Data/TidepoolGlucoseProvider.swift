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

// MARK: - Sharing

extension TidepoolGlucoseProvider: ShareProvider {
    func shareEntries() async throws -> [ShareEntry] {
        try await withSession { session in
            async let clinics = client.clinicsForPatient(session: session)
            async let members = client.careTeam(session: session)
            async let invites = client.sentInvites(session: session)
            let (sharedClinics, careTeam, sentInvites) = try await (clinics, members, invites)

            var entries: [ShareEntry] = []
            entries += sharedClinics.map {
                ShareEntry(id: $0.clinic.id, kind: .clinic, name: $0.clinic.name, status: .sharing, permissions: $0.permissions)
            }
            entries += careTeam.map {
                ShareEntry(id: $0.userID, kind: .member, name: $0.name, email: $0.email, status: .sharing, permissions: $0.permissions)
            }
            for invite in sentInvites {
                let status: ShareEntry.Status
                switch invite.status {
                case "pending": status = .inviteSent
                case "declined": status = .inviteDeclined
                default: continue
                }
                if let clinicID = invite.clinicID {
                    // The invite carries only the clinic ID; a failed name lookup still lists the invite.
                    let name = try? await client.clinic(session: session, id: clinicID).name
                    entries.append(ShareEntry(
                        id: invite.key, kind: .clinic, name: name, status: status, permissions: invite.permissions,
                        inviteKey: invite.key, clinicID: clinicID, created: invite.created
                    ))
                } else if let email = invite.email {
                    entries.append(ShareEntry(
                        id: invite.key, kind: .member, email: email, status: status, permissions: invite.permissions,
                        inviteKey: invite.key, created: invite.created
                    ))
                }
            }
            return entries
        }
    }

    func clinic(shareCode: String) async throws -> ClinicSummary {
        do {
            return try await withSession { session in
                try await client.clinic(session: session, shareCode: shareCode)
            }
        } catch TidepoolError.notFound {
            throw ShareError.clinicNotFound
        }
    }

    func inviteClinic(shareCode: String, permissions: SharePermissions) async throws {
        do {
            try await withSession { session in
                try await client.inviteClinic(session: session, shareCode: shareCode, permissions: permissions)
            }
        } catch TidepoolError.notFound {
            throw ShareError.clinicNotFound
        } catch TidepoolError.conflict(let reason) {
            throw reason.map(ShareError.rejected) ?? .alreadySharing
        }
    }

    func inviteMember(email: String, permissions: SharePermissions) async throws {
        do {
            try await withSession { session in
                try await client.inviteMember(session: session, email: email, permissions: permissions)
            }
        } catch TidepoolError.conflict(let reason) {
            throw ShareError.rejected(reason ?? "You are already sharing with this care team member. Please enter a new email.")
        }
    }

    func setUpload(_ allowed: Bool, for entry: ShareEntry) async throws {
        var permissions = entry.permissions
        permissions.upload = allowed
        try await withSession { session in
            switch entry.kind {
            case .clinic:
                try await client.setClinicPermissions(session: session, clinicID: entry.id, permissions: permissions)
            case .member:
                try await client.setMemberPermissions(session: session, memberID: entry.id, permissions: permissions)
            }
        }
    }

    func resendInvite(_ entry: ShareEntry) async throws {
        guard let key = entry.inviteKey else { return }
        try await withSession { session in
            try await client.resendInvite(session: session, key: key)
        }
    }

    func revoke(_ entry: ShareEntry) async throws {
        try await withSession { session in
            switch (entry.kind, entry.isPending) {
            case (.clinic, false):
                try await client.leaveClinic(session: session, clinicID: entry.id)
            case (.member, false):
                try await client.setMemberPermissions(session: session, memberID: entry.id, permissions: nil)
            case (.clinic, true):
                guard let clinicID = entry.clinicID, let key = entry.inviteKey else { return }
                try await client.cancelClinicInvite(session: session, clinicID: clinicID, key: key)
            case (.member, true):
                guard let email = entry.email else { return }
                try await client.cancelMemberInvite(session: session, email: email)
            }
        }
    }
}
