//
//  ViewableAccount.swift
//  Blipper
//

import Foundation

/// A Tidepool account the signed-in login can view: its own, one shared with it, or a patient of
/// a clinic it works in.
nonisolated struct ViewableAccount: Sendable, Codable, Hashable, Identifiable {
    /// Tidepool user ID.
    let id: String
    /// The person's name, or the login's email for its own account.
    let name: String
    let isOwn: Bool
    /// The clinic this account is viewed through, for a clinician looking at a patient.
    var clinicName: String? = nil

    var isClinicPatient: Bool { clinicName != nil }
}
