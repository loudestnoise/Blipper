//
//  Note.swift
//  Blipper
//
//  A free-text note pinned to a moment, as in Tidepool Mobile and Tidepool Web.
//

import Foundation

nonisolated struct Note: Identifiable, Hashable, Sendable {
    let id: String
    let text: String
    /// The moment the note is about, which the user can set apart from when it was written.
    let timestamp: Date
    /// Who wrote it, when that was someone other than the account holder (such as a care team member in Tidepool Web).
    let authorName: String?

    init(id: String, text: String, timestamp: Date, authorName: String? = nil) {
        self.id = id
        self.text = text
        self.timestamp = timestamp
        self.authorName = authorName
    }
}
