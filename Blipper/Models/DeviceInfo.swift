//
//  DeviceInfo.swift
//  Blipper
//
//  What the Tidepool "Devices" view shows: each uploading device and its current settings.
//

import Foundation

nonisolated struct DeviceInfo: Identifiable, Sendable {
    let id: String
    let manufacturer: String?
    let model: String?
    let serialNumber: String?
    let lastUpload: Date?
    /// Tidepool device tags, e.g. "cgm", "insulin-pump", "bgm".
    let tags: [String]
    let pumpSettings: PumpSettings?
    let cgmSettings: CGMSettings?

    var displayName: String {
        [manufacturer, model].compactMap { $0 }.joined(separator: " ").nilIfEmpty ?? id
    }

    var kindSymbol: String {
        if pumpSettings != nil || tags.contains("insulin-pump") { return "syringe" }
        if cgmSettings != nil || tags.contains("cgm") { return "sensor" }
        if tags.contains("bgm") { return "drop" }
        return "cpu"
    }
}

/// A value that applies from `start` (seconds after midnight) until the next entry.
nonisolated struct ScheduleEntry: Identifiable, Sendable {
    let start: TimeInterval
    let value: Double

    var id: TimeInterval { start }
}

nonisolated struct TargetEntry: Identifiable, Sendable {
    let start: TimeInterval
    let low: Double?
    let high: Double?
    let target: Double?

    var id: TimeInterval { start }

    var label: String {
        switch (low, high, target) {
        case let (low?, high?, _): "\(Int(low))–\(Int(high))"
        case let (_, _, target?): "\(Int(target))"
        case let (low?, nil, nil): "≥ \(Int(low))"
        case let (nil, high?, nil): "≤ \(Int(high))"
        default: "—"
        }
    }
}

nonisolated struct PumpSettings: Sendable {
    let updated: Date
    let activeSchedule: String?
    /// Basal schedules by name, U/hr.
    let basalSchedules: [String: [ScheduleEntry]]
    /// g carb per unit of insulin.
    let carbRatios: [ScheduleEntry]
    /// mg/dL per unit of insulin.
    let insulinSensitivities: [ScheduleEntry]
    /// mg/dL.
    let targets: [TargetEntry]

    var activeBasalSchedule: [ScheduleEntry] {
        if let activeSchedule, let schedule = basalSchedules[activeSchedule] { return schedule }
        return basalSchedules.sorted { $0.key < $1.key }.first?.value ?? []
    }
}

nonisolated struct CGMSettings: Sendable {
    let updated: Date
    let transmitterID: String?
    /// mg/dL, when the alert is enabled.
    let lowAlert: Double?
    let highAlert: Double?
}

nonisolated extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
