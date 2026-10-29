//
//  Sharing.swift
//  Blipper
//
//  Who can see the account's data: care team members and clinics, plus the invites still waiting on them.
//

import Foundation

/// What a care team member or clinic may do with the account's data.
nonisolated struct SharePermissions: Sendable, Equatable {
    var view = true
    var note = true
    var upload = false

    static let viewOnly = SharePermissions()
    static let viewAndUpload = SharePermissions(upload: true)

    /// Builds from the keys of a Tidepool permissions map such as `{"view": {}, "upload": {}}`.
    init(keys: some Sequence<String>) {
        let set = Set(keys)
        view = set.contains("view")
        note = set.contains("note")
        upload = set.contains("upload")
    }

    init(view: Bool = true, note: Bool = true, upload: Bool = false) {
        self.view = view
        self.note = note
        self.upload = upload
    }

    /// The Tidepool wire form: a map whose keys are the granted permissions.
    var wireForm: [String: [String: String]] {
        var map: [String: [String: String]] = [:]
        if view { map["view"] = [:] }
        if note { map["note"] = [:] }
        if upload { map["upload"] = [:] }
        return map
    }
}

/// A clinic as returned by a share code lookup.
nonisolated struct ClinicSummary: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let shareCode: String
}

/// One row of the Sharing screen: someone who has, or has been invited to have, access to the account.
nonisolated struct ShareEntry: Identifiable, Sendable, Equatable {
    enum Kind: Sendable {
        case clinic, member
    }

    enum Status: Sendable {
        case sharing, inviteSent, inviteDeclined
    }

    /// Clinic ID or member user ID when sharing; the invite key while pending.
    let id: String
    let kind: Kind
    let name: String?
    let email: String?
    let status: Status
    let permissions: SharePermissions
    /// Confirmation key of a pending invite.
    let inviteKey: String?
    /// The clinic a pending clinic invite was sent to.
    let clinicID: String?
    let created: Date?

    init(
        id: String,
        kind: Kind,
        name: String? = nil,
        email: String? = nil,
        status: Status,
        permissions: SharePermissions,
        inviteKey: String? = nil,
        clinicID: String? = nil,
        created: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.email = email
        self.status = status
        self.permissions = permissions
        self.inviteKey = inviteKey
        self.clinicID = clinicID
        self.created = created
    }

    var displayName: String { name?.nilIfEmpty ?? email ?? id }
    var isPending: Bool { status != .sharing }

    var kindLabel: String {
        switch kind {
        case .clinic: "Clinic"
        case .member: "Care Team Member"
        }
    }

    var statusLabel: String {
        switch status {
        case .sharing: "Sharing"
        case .inviteSent: "Invite sent"
        case .inviteDeclined: "Invite declined"
        }
    }
}

/// The 12-character clinic share code: three dash-separated groups drawn from an alphabet that
/// leaves out I, O, 0 and 1.
nonisolated enum ShareCode {
    static let alphabet = Set("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    static let formattedLength = 14

    /// Upper-cases `raw`, drops anything outside the alphabet, and inserts dashes after each group of four.
    static func format(_ raw: String) -> String {
        let letters = raw.uppercased().filter { alphabet.contains($0) }.prefix(12)
        var out = ""
        for (index, letter) in letters.enumerated() {
            if index > 0, index % 4 == 0 { out.append("-") }
            out.append(letter)
        }
        return out
    }

    /// True for a fully entered code in `XXXX-XXXX-XXXX` form.
    static func isComplete(_ formatted: String) -> Bool {
        formatted.count == formattedLength && format(formatted) == formatted
    }
}

/// Problems the Sharing screens report in the user's words.
nonisolated enum ShareError: LocalizedError, Equatable {
    case clinicNotFound
    case alreadySharing
    case invalidEmail
    case rejected(String)

    var errorDescription: String? {
        switch self {
        case .clinicNotFound: "We were unable to find a clinic with that share code."
        case .alreadySharing: "You are already sharing with this clinic. Please enter a new share code."
        case .invalidEmail: "Please enter a valid email address."
        case .rejected(let reason): reason
        }
    }
}
