//
//  ShareProvider.swift
//  Blipper
//

import Foundation

/// Source of sharing state and the actions the Sharing screen can take on it.
nonisolated protocol ShareProvider: Sendable {
    /// Everyone the account is sharing with, followed by invites still pending.
    func shareEntries() async throws -> [ShareEntry]
    /// Resolves a formatted share code (`XXXX-XXXX-XXXX`) to a clinic; throws `ShareError.clinicNotFound`.
    func clinic(shareCode: String) async throws -> ClinicSummary
    func inviteClinic(shareCode: String, permissions: SharePermissions) async throws
    func inviteMember(email: String, permissions: SharePermissions) async throws
    /// Grants or removes upload permission for someone already sharing.
    func setUpload(_ allowed: Bool, for entry: ShareEntry) async throws
    /// Sends a pending care team invite again.
    func resendInvite(_ entry: ShareEntry) async throws
    /// Revokes a pending invite, removes a member, or leaves a clinic, depending on `entry`.
    func revoke(_ entry: ShareEntry) async throws
}

/// In-memory sharing state so the Sharing screen works under `-useMockData`.
actor MockShareProvider: ShareProvider {
    /// Any complete share code resolves to this clinic, except codes starting with `XXXX`, which are not found.
    static let mockClinic = ClinicSummary(id: "mock-clinic", name: "Seastar Endocrinology", shareCode: "BLPR-CLNC-2345")

    private var entries: [ShareEntry]

    init() {
        let now = Date()
        entries = [
            ShareEntry(
                id: Self.mockClinic.id,
                kind: .clinic,
                name: Self.mockClinic.name,
                status: .sharing,
                permissions: .viewAndUpload
            ),
            ShareEntry(
                id: "mock-member-1",
                kind: .member,
                name: "Catherine Catfish",
                email: "demo-catherine@example.com",
                status: .sharing,
                permissions: .viewOnly
            ),
            ShareEntry(
                id: "mock-invite-1",
                kind: .member,
                email: "jill@example.com",
                status: .inviteSent,
                permissions: .viewAndUpload,
                inviteKey: "mock-invite-1",
                created: now.addingTimeInterval(-2 * 86_400)
            ),
        ]
    }

    func shareEntries() async throws -> [ShareEntry] {
        try await Task.sleep(for: .milliseconds(200))
        return entries
    }

    func clinic(shareCode: String) async throws -> ClinicSummary {
        try await Task.sleep(for: .milliseconds(300))
        guard ShareCode.isComplete(shareCode), !shareCode.hasPrefix("XXXX") else { throw ShareError.clinicNotFound }
        return ClinicSummary(id: Self.mockClinic.id, name: Self.mockClinic.name, shareCode: shareCode)
    }

    func inviteClinic(shareCode: String, permissions: SharePermissions) async throws {
        let clinic = try await clinic(shareCode: shareCode)
        guard !entries.contains(where: { $0.kind == .clinic && ($0.id == clinic.id || $0.clinicID == clinic.id) }) else {
            throw ShareError.alreadySharing
        }
        let key = "mock-invite-\(UUID().uuidString.prefix(8))"
        entries.append(ShareEntry(
            id: key, kind: .clinic, name: clinic.name, status: .inviteSent,
            permissions: permissions, inviteKey: key, clinicID: clinic.id, created: Date()
        ))
    }

    func inviteMember(email: String, permissions: SharePermissions) async throws {
        try await Task.sleep(for: .milliseconds(300))
        guard !entries.contains(where: { $0.email?.lowercased() == email.lowercased() }) else {
            throw ShareError.rejected("You are already sharing with this care team member. Please enter a new email.")
        }
        let key = "mock-invite-\(UUID().uuidString.prefix(8))"
        entries.append(ShareEntry(
            id: key, kind: .member, email: email, status: .inviteSent,
            permissions: permissions, inviteKey: key, created: Date()
        ))
    }

    func setUpload(_ allowed: Bool, for entry: ShareEntry) async throws {
        try await Task.sleep(for: .milliseconds(200))
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        let old = entries[index]
        var permissions = old.permissions
        permissions.upload = allowed
        entries[index] = ShareEntry(
            id: old.id, kind: old.kind, name: old.name, email: old.email, status: old.status,
            permissions: permissions, inviteKey: old.inviteKey, clinicID: old.clinicID, created: old.created
        )
    }

    func resendInvite(_ entry: ShareEntry) async throws {
        try await Task.sleep(for: .milliseconds(200))
    }

    func revoke(_ entry: ShareEntry) async throws {
        try await Task.sleep(for: .milliseconds(200))
        entries.removeAll { $0.id == entry.id }
    }
}
