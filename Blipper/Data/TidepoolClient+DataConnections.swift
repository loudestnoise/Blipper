//
//  TidepoolClient+DataConnections.swift
//  Blipper
//
//  The calls behind the Data Connections dialog in Tidepool Web. Connecting a provider means
//  minting a restricted token scoped to `/v1/oauth/{provider}` and sending the browser to
//  `/v1/oauth/{provider}/authorize?restricted_token=…`; the platform redirects to the provider,
//  exchanges the code, creates the data source, and lands the browser on
//  app.tidepool.org/oauth/{provider}/authorized (or /declined).
//

import Foundation

extension TidepoolClient {
    /// GET /v1/users/{userId}/data_sources
    func dataSources(session: TidepoolSession) async throws -> [DataSource] {
        let data: Data
        do {
            data = try await send(session: session, method: "GET", path: "v1/users/\(session.userID)/data_sources")
        } catch TidepoolError.notFound {
            return []
        }
        let wire = try JSONDecoder().decode([WireDataSource].self, from: data)
        return wire.map {
            DataSource(
                id: $0.id,
                providerName: $0.providerName,
                state: DataSource.State(rawValue: $0.state ?? ""),
                createdTime: $0.createdTime.flatMap(Self.parseISOTime),
                modifiedTime: $0.modifiedTime.flatMap(Self.parseISOTime),
                lastImportTime: $0.lastImportTime.flatMap(Self.parseISOTime),
                latestDataTime: $0.latestDataTime.flatMap(Self.parseISOTime)
            )
        }
    }

    /// POST /v1/users/{userId}/restricted_tokens, then the authorize URL that token unlocks.
    /// The token is single-purpose and expires on its own; Tidepool deletes it once the provider redirects back.
    func authorizationURL(session: TidepoolSession, provider: DataProvider) async throws -> URL {
        let body = WireRestrictedTokenRequest(paths: [provider.oauthPath])
        let data = try await send(session: session, method: "POST", path: "v1/users/\(session.userID)/restricted_tokens", body: body)
        let token = try JSONDecoder().decode(WireRestrictedToken.self, from: data)
        var components = URLComponents(
            url: Self.base.appending(path: "v1/oauth/\(provider.providerName)/authorize"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "restricted_token", value: token.id)]
        guard let url = components.url else { throw TidepoolError.badResponse }
        return url
    }

    /// DELETE /v1/oauth/{providerName}/authorize
    func revokeAuthorization(session: TidepoolSession, provider: DataProvider) async throws {
        _ = try await send(session: session, method: "DELETE", path: "v1/oauth/\(provider.providerName)/authorize")
    }

    // MARK: Wire formats

    private struct WireDataSource: Decodable {
        let id: String
        let providerName: String
        let state: String?
        let createdTime: String?
        let modifiedTime: String?
        let lastImportTime: String?
        let latestDataTime: String?
    }

    private struct WireRestrictedTokenRequest: Encodable {
        let paths: [String]
    }

    private struct WireRestrictedToken: Decodable {
        let id: String
    }
}
