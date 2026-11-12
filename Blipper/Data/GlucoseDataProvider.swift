//
//  GlucoseDataProvider.swift
//  Blipper
//

import Foundation

/// Source of glucose readings. Swap the implementation to wire a real backend.
nonisolated protocol GlucoseDataProvider: Sendable {
    /// Returns readings with `timestamp` in `interval`, sorted ascending by time.
    func readings(in interval: DateInterval) async throws -> [GlucoseReading]

    /// When the newest CGM reading was taken; `nil` if there is none or the source cannot say.
    func latestReadingDate() async throws -> Date?
}

extension GlucoseDataProvider {
    func latestReadingDate() async throws -> Date? { nil }
}

/// The newest day a screen may show when an account's data stops before today.
nonisolated enum DataEnd {
    /// Start of the day of `newest`, or `nil` when that is today (or unknown), meaning no limit.
    static func day(newest: Date?, calendar: Calendar) -> Date? {
        guard let newest else { return nil }
        let day = calendar.startOfDay(for: newest)
        return day < calendar.startOfDay(for: Date()) ? day : nil
    }
}
