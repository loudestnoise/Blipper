//
//  GlucoseDataProvider.swift
//  Blipper
//

import Foundation

/// Source of glucose readings. Swap the implementation to wire a real backend.
nonisolated protocol GlucoseDataProvider: Sendable {
    /// Returns readings with `timestamp` in `interval`, sorted ascending by time.
    func readings(in interval: DateInterval) async throws -> [GlucoseReading]
}
