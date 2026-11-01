//
//  NoteProvider.swift
//  Blipper
//

import Foundation

/// Source of notes and the one action the Notes screen takes on them.
nonisolated protocol NoteProvider: Sendable {
    /// Every note on the account, newest first.
    func notes() async throws -> [Note]
    /// Saves a new note and returns it as stored.
    func addNote(text: String, timestamp: Date) async throws -> Note
}

/// In-memory notes so the Notes screen works under `-useMockData`.
actor MockNoteProvider: NoteProvider {
    private var stored: [Note]

    init() {
        // Five-minute boundaries, so markers line up with the mock CGM samples.
        let now = Date()
        let base = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 300).rounded(.down) * 300)
        stored = [
            Note(id: "mock-1", text: "Went for a walk", timestamp: base.addingTimeInterval(-2.5 * 3600)),
            Note(id: "mock-2", text: "Pizza night, split the bolus", timestamp: base.addingTimeInterval(-22 * 3600)),
            Note(id: "mock-3", text: "Changed pump site", timestamp: base.addingTimeInterval(-47 * 3600), authorName: "Care team member"),
        ]
    }

    func notes() async throws -> [Note] {
        try await Task.sleep(for: .milliseconds(250))
        return stored.sorted { $0.timestamp > $1.timestamp }
    }

    func addNote(text: String, timestamp: Date) async throws -> Note {
        try await Task.sleep(for: .milliseconds(300))
        let note = Note(id: UUID().uuidString, text: text, timestamp: timestamp)
        stored.append(note)
        return note
    }
}
