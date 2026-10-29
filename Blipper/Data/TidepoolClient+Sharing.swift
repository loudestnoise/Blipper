//
//  TidepoolClient+Sharing.swift
//  Blipper
//
//  The calls Tidepool Web makes from its Share page: clinic share codes, care team invites, and
//  the permissions behind them. Paths mirror tidepool-org/platform-client, which is what the web
//  app uses; `POST /confirm/send/invite/{userId}/clinic` is served by hydrophone but is not in the
//  published OpenAPI reference.
//

import Foundation
import OSLog

/// A care team member who can see the account's data.
nonisolated struct CareTeamMember: Sendable {
    let userID: String
    let name: String?
    let email: String?
    let permissions: SharePermissions
}

/// A clinic the account shares with, and what it may do.
nonisolated struct ClinicRelationship: Sendable {
    let clinic: ClinicSummary
    let permissions: SharePermissions
}

/// An invitation this account sent that has not been accepted.
nonisolated struct SentInvite: Sendable {
    let key: String
    let email: String?
    let clinicID: String?
    /// `pending`, `declined`, `completed`, or `canceled`.
    let status: String
    let permissions: SharePermissions
    let created: Date?
}

extension TidepoolClient {
    private static let shareLog = Logger(subsystem: "com.PickleTron.Blipper", category: "sharing")

    // MARK: Lookups

    /// GET /v1/clinics/share_code/{shareCode}
    func clinic(session: TidepoolSession, shareCode: String) async throws -> ClinicSummary {
        let data = try await send(session: session, method: "GET", path: "v1/clinics/share_code/\(shareCode)")
        let wire = try JSONDecoder().decode(WireClinic.self, from: data)
        return ClinicSummary(id: wire.id, name: wire.name, shareCode: wire.shareCode ?? shareCode)
    }

    /// GET /v1/clinics/{clinicId}
    func clinic(session: TidepoolSession, id: String) async throws -> ClinicSummary {
        let data = try await send(session: session, method: "GET", path: "v1/clinics/\(id)")
        let wire = try JSONDecoder().decode(WireClinic.self, from: data)
        return ClinicSummary(id: wire.id, name: wire.name, shareCode: wire.shareCode ?? "")
    }

    /// GET /v1/patients/{userId}/clinics — clinics this account is a patient of.
    func clinicsForPatient(session: TidepoolSession) async throws -> [ClinicRelationship] {
        let data: Data
        do {
            data = try await send(session: session, method: "GET", path: "v1/patients/\(session.userID)/clinics")
        } catch TidepoolError.notFound {
            return []
        }
        let wire = try JSONDecoder().decode([WireClinicRelationship].self, from: data)
        Self.shareLog.notice("clinics: \(wire.count) relationships")
        return wire.map {
            ClinicRelationship(
                clinic: ClinicSummary(id: $0.clinic.id, name: $0.clinic.name, shareCode: $0.clinic.shareCode ?? ""),
                permissions: SharePermissions(keys: $0.patient?.permissions?.keys ?? [])
            )
        }
    }

    /// GET /metadata/users/{userId}/users — accounts linked to this one. Members of the care team are
    /// the ones holding `trusteePermissions`; Tidepool's data donation accounts are left out.
    func careTeam(session: TidepoolSession) async throws -> [CareTeamMember] {
        let data: Data
        do {
            data = try await send(session: session, method: "GET", path: "metadata/users/\(session.userID)/users")
        } catch TidepoolError.notFound {
            return []
        }
        let users = try JSONDecoder().decode([WireAssociatedUser].self, from: data)
        let members = users.compactMap { user -> CareTeamMember? in
            guard let keys = user.trusteePermissions?.keys, !keys.isEmpty else { return nil }
            let email = user.emails?.first ?? user.username
            if Self.isDataDonationAccount(email) { return nil }
            return CareTeamMember(
                userID: user.userid,
                name: user.profile?.fullName,
                email: email,
                permissions: SharePermissions(keys: keys)
            )
        }
        Self.shareLog.notice("care team: \(users.count) linked accounts, \(members.count) members")
        return members
    }

    /// GET /confirm/invite/{userId} — invitations this account sent that are still open.
    func sentInvites(session: TidepoolSession) async throws -> [SentInvite] {
        let data: Data
        do {
            data = try await send(session: session, method: "GET", path: "confirm/invite/\(session.userID)")
        } catch TidepoolError.notFound {
            return []
        }
        let wire = try JSONDecoder().decode([WireConfirmation].self, from: data)
        let invites = wire
            .filter { !Self.isDataDonationAccount($0.email) }
            .map {
                SentInvite(
                    key: $0.key,
                    email: $0.email?.nilIfEmpty,
                    clinicID: $0.clinicId?.nilIfEmpty,
                    status: $0.status,
                    permissions: SharePermissions(keys: $0.context?.keys ?? []),
                    created: $0.created.flatMap(Self.parseISOTime)
                )
            }
        Self.shareLog.notice("invites: \(invites.count) open")
        return invites
    }

    // MARK: Invites

    /// POST /confirm/send/invite/{userId}/clinic
    func inviteClinic(session: TidepoolSession, shareCode: String, permissions: SharePermissions) async throws {
        let body = WireClinicInvite(shareCode: shareCode, permissions: permissions.wireForm)
        _ = try await send(session: session, method: "POST", path: "confirm/send/invite/\(session.userID)/clinic", body: body)
    }

    /// POST /confirm/send/invite/{userId}
    func inviteMember(session: TidepoolSession, email: String, permissions: SharePermissions) async throws {
        let body = WireMemberInvite(email: email, permissions: permissions.wireForm)
        _ = try await send(session: session, method: "POST", path: "confirm/send/invite/\(session.userID)", body: body)
    }

    /// PATCH /confirm/resend/invite/{inviteId} — care team invites only; the server refuses clinic invites here.
    func resendInvite(session: TidepoolSession, key: String) async throws {
        _ = try await send(session: session, method: "PATCH", path: "confirm/resend/invite/\(key)")
    }

    /// PUT /confirm/{userId}/invited/{email}
    func cancelMemberInvite(session: TidepoolSession, email: String) async throws {
        _ = try await send(session: session, method: "PUT", path: "confirm/\(session.userID)/invited/\(email)")
    }

    /// DELETE /v1/clinics/{clinicId}/invites/patients/{inviteId}
    func cancelClinicInvite(session: TidepoolSession, clinicID: String, key: String) async throws {
        _ = try await send(session: session, method: "DELETE", path: "v1/clinics/\(clinicID)/invites/patients/\(key)")
    }

    // MARK: Permissions

    /// POST /access/{userId}/{memberId}; a `nil` body removes the member.
    func setMemberPermissions(session: TidepoolSession, memberID: String, permissions: SharePermissions?) async throws {
        let path = "access/\(session.userID)/\(memberID)"
        if let permissions {
            _ = try await send(session: session, method: "POST", path: path, body: permissions.wireForm)
        } else {
            _ = try await send(session: session, method: "POST", path: path, rawBody: Data("null".utf8))
        }
    }

    /// PUT /v1/clinics/{clinicId}/patients/{patientId}/permissions
    func setClinicPermissions(session: TidepoolSession, clinicID: String, permissions: SharePermissions) async throws {
        _ = try await send(
            session: session, method: "PUT",
            path: "v1/clinics/\(clinicID)/patients/\(session.userID)/permissions",
            body: permissions.wireForm
        )
    }

    /// DELETE /v1/clinics/{clinicId}/patients/{patientId}
    func leaveClinic(session: TidepoolSession, clinicID: String) async throws {
        _ = try await send(session: session, method: "DELETE", path: "v1/clinics/\(clinicID)/patients/\(session.userID)")
    }

    // MARK: Request plumbing

    /// Sends an authenticated JSON request and maps Tidepool's status codes to `TidepoolError`.
    func send<B: Encodable>(session: TidepoolSession, method: String, path: String, body: B) async throws -> Data {
        try await send(session: session, method: method, path: path, rawBody: try JSONEncoder().encode(body))
    }

    func send(session: TidepoolSession, method: String, path: String, rawBody: Data? = nil) async throws -> Data {
        var request = URLRequest(url: Self.base.appending(path: path))
        request.httpMethod = method
        request.setValue(session.token, forHTTPHeaderField: "X-Tidepool-Session-Token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let rawBody {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = rawBody
        }

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TidepoolError.badResponse }
        // Status and path only; never the body, which may carry names or emails.
        Self.shareLog.notice("\(method, privacy: .public) \(path.split(separator: "/").first ?? "", privacy: .public): \(http.statusCode)")
        switch http.statusCode {
        case 200...299: return data
        case 401: throw TidepoolError.invalidCredentials
        case 403: throw TidepoolError.forbidden
        case 404: throw TidepoolError.notFound
        case 409: throw TidepoolError.conflict(Self.reason(in: data))
        default: throw TidepoolError.http(http.statusCode)
        }
    }

    /// The human-readable message Tidepool services put in an error body, if any.
    private static func reason(in data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        for key in ["reason", "message", "error"] {
            if let text = object[key] as? String, !text.isEmpty { return text }
        }
        return nil
    }

    private static func isDataDonationAccount(_ email: String?) -> Bool {
        guard let email = email?.lowercased() else { return false }
        return email.hasPrefix("bigdata") && email.hasSuffix("@tidepool.org")
    }

    private static let isoTimeParsers: [ISO8601DateFormatter] = {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let whole = ISO8601DateFormatter()
        whole.formatOptions = [.withInternetDateTime]
        return [fractional, whole]
    }()

    /// RFC 3339 with or without fractional seconds, as Tidepool services emit.
    static func parseISOTime(_ string: String) -> Date? {
        for parser in isoTimeParsers {
            if let date = parser.date(from: string) { return date }
        }
        return nil
    }

    // MARK: Wire formats

    /// A Tidepool permissions map such as `{"view": {}, "upload": {}}`; only the keys matter.
    private struct WirePermissionMap: Decodable {
        let keys: [String]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: AnyKey.self)
            keys = container.allKeys.map(\.stringValue)
        }
    }

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    private struct WireClinic: Decodable {
        let id: String
        let name: String
        let shareCode: String?
    }

    private struct WireClinicRelationship: Decodable {
        struct Patient: Decodable {
            let permissions: WirePermissionMap?
        }
        let clinic: WireClinic
        let patient: Patient?
    }

    private struct WireAssociatedUser: Decodable {
        struct Profile: Decodable {
            let fullName: String?
        }
        let userid: String
        let username: String?
        let emails: [String]?
        let profile: Profile?
        let trusteePermissions: WirePermissionMap?
    }

    private struct WireConfirmation: Decodable {
        let key: String
        let status: String
        let email: String?
        let clinicId: String?
        let context: WirePermissionMap?
        let created: String?

        private enum CodingKeys: String, CodingKey {
            case key, status, email, clinicId, context, created
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            key = try c.decode(String.self, forKey: .key)
            status = try c.decodeIfPresent(String.self, forKey: .status) ?? "pending"
            email = try c.decodeIfPresent(String.self, forKey: .email)
            clinicId = try c.decodeIfPresent(String.self, forKey: .clinicId)
            created = try c.decodeIfPresent(String.self, forKey: .created)
            // `context` is free-form on the server; anything other than a permissions map is ignored.
            context = try? c.decodeIfPresent(WirePermissionMap.self, forKey: .context)
        }
    }

    private struct WireClinicInvite: Encodable {
        let shareCode: String
        let permissions: [String: [String: String]]
    }

    private struct WireMemberInvite: Encodable {
        let email: String
        let permissions: [String: [String: String]]
    }
}
