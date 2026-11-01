//
//  TidepoolClient+Notes.swift
//  Blipper
//
//  Notes live in Tidepool's message service (tidepool-org/message-api), where Tidepool Web and
//  Tidepool Mobile keep them. A note is a top-level message on the account; replies are ignored.
//

import Foundation

extension TidepoolClient {
    /// GET /message/notes/{userId}. The message service answers 404 when there are none.
    func notes(session: TidepoolSession) async throws -> [Note] {
        let data: Data
        do {
            data = try await send(session: session, method: "GET", path: "message/notes/\(session.userID)")
        } catch TidepoolError.notFound {
            return []
        }
        let wire = try JSONDecoder().decode(WireMessages.self, from: data)
        return wire.messages
            .compactMap { message in
                guard let timestamp = Self.parseISOTime(message.timestamp) else { return nil }
                let author = message.userid == session.userID ? nil : message.user?.fullName
                return Note(id: message.id, text: message.messagetext ?? "", timestamp: timestamp, authorName: author)
            }
            .sorted { $0.timestamp > $1.timestamp }
    }

    /// POST /message/send/{userId}; the service requires `guid`, `timestamp`, and `messagetext`.
    func addNote(session: TidepoolSession, text: String, timestamp: Date) async throws -> Note {
        let body = WireNewNote(message: WireNewNote.Message(
            guid: UUID().uuidString,
            userid: session.userID,
            groupid: session.userID,
            timestamp: Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(timestamp),
            messagetext: text
        ))
        let data = try await send(session: session, method: "POST", path: "message/send/\(session.userID)", body: body)
        let created = try JSONDecoder().decode(WireCreated.self, from: data)
        return Note(id: created.id, text: text, timestamp: timestamp)
    }

    // MARK: Wire formats

    private struct WireMessages: Decodable {
        let messages: [WireMessage]
    }

    private struct WireMessage: Decodable {
        let id: String
        let userid: String?
        let timestamp: String
        let messagetext: String?
        let user: WireProfile?
    }

    private struct WireProfile: Decodable {
        let fullName: String?
    }

    private struct WireNewNote: Encodable {
        struct Message: Encodable {
            let guid: String
            let userid: String
            let groupid: String
            let timestamp: String
            let messagetext: String
        }
        let message: Message
    }

    private struct WireCreated: Decodable {
        let id: String
    }
}
