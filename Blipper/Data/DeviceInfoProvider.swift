//
//  DeviceInfoProvider.swift
//  Blipper
//

import Foundation

/// Source of device and settings information for the Settings tab.
nonisolated protocol DeviceInfoProvider: Sendable {
    /// Devices that have uploaded recently, most recent upload first.
    func devices() async throws -> [DeviceInfo]
}

/// Static devices so the Settings tab works offline.
nonisolated struct MockDeviceInfoProvider: DeviceInfoProvider {
    func devices() async throws -> [DeviceInfo] {
        try await Task.sleep(for: .milliseconds(200))
        let now = Date()
        let hour: TimeInterval = 3600
        return [
            DeviceInfo(
                id: "mock-cgm",
                manufacturer: "Dexcom",
                model: "G7",
                serialNumber: "MOCK-CGM-0001",
                lastUpload: now.addingTimeInterval(-4 * 60),
                tags: ["cgm"],
                pumpSettings: nil,
                cgmSettings: CGMSettings(
                    updated: now.addingTimeInterval(-3 * 86_400),
                    transmitterID: "MOCK01",
                    lowAlert: 70,
                    highAlert: 250
                )
            ),
            DeviceInfo(
                id: "mock-pump",
                manufacturer: "Insulet",
                model: "Omnipod DASH",
                serialNumber: "MOCK-PUMP-0001",
                lastUpload: now.addingTimeInterval(-25 * 60),
                tags: ["insulin-pump"],
                pumpSettings: PumpSettings(
                    updated: now.addingTimeInterval(-9 * 86_400),
                    activeSchedule: "Default",
                    basalSchedules: [
                        "Default": [
                            ScheduleEntry(start: 0, value: 0.80),
                            ScheduleEntry(start: 3 * hour, value: 0.95),
                            ScheduleEntry(start: 7 * hour, value: 1.10),
                            ScheduleEntry(start: 12 * hour, value: 0.90),
                            ScheduleEntry(start: 22 * hour, value: 0.80),
                        ],
                        "Weekend": [
                            ScheduleEntry(start: 0, value: 0.75),
                            ScheduleEntry(start: 8 * hour, value: 1.00),
                        ],
                    ],
                    carbRatios: [
                        ScheduleEntry(start: 0, value: 12),
                        ScheduleEntry(start: 6 * hour, value: 9),
                        ScheduleEntry(start: 11 * hour, value: 10),
                        ScheduleEntry(start: 17 * hour, value: 11),
                    ],
                    insulinSensitivities: [
                        ScheduleEntry(start: 0, value: 45),
                        ScheduleEntry(start: 6 * hour, value: 40),
                        ScheduleEntry(start: 21 * hour, value: 50),
                    ],
                    targets: [
                        TargetEntry(start: 0, low: 100, high: 110, target: nil),
                        TargetEntry(start: 7 * hour, low: 95, high: 105, target: nil),
                    ]
                ),
                cgmSettings: nil
            ),
        ]
    }
}
