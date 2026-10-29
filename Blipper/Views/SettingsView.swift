//
//  SettingsView.swift
//  Blipper
//

import SwiftUI

struct SettingsView: View {
    let email: String?
    let deviceProvider: any DeviceInfoProvider
    let shareProvider: any ShareProvider
    let onSignOut: () -> Void

    @State private var devices: [DeviceInfo] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var confirmSignOut = false
    @State private var path: [SettingsRoute] = Self.openSharingOnLaunch ? [.sharing] : []

    private enum SettingsRoute: Hashable {
        case sharing
        case device(String)
    }

    /// `-openSharing` starts on the Sharing screen (Debug builds only).
    private static var openSharingOnLaunch: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-openSharing")
        #else
        false
        #endif
    }

    init(
        email: String? = nil,
        deviceProvider: any DeviceInfoProvider = MockDeviceInfoProvider(),
        shareProvider: any ShareProvider = MockShareProvider(),
        onSignOut: @escaping () -> Void = {}
    ) {
        self.email = email
        self.deviceProvider = deviceProvider
        self.shareProvider = shareProvider
        self.onSignOut = onSignOut
    }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section {
                    LabeledContent("Tidepool", value: email ?? "Mock data")
                    NavigationLink(value: SettingsRoute.sharing) {
                        Label("Sharing", systemImage: "person.2")
                    }
                    Button("Sign Out", role: .destructive) { confirmSignOut = true }
                } header: {
                    Text("Account")
                } footer: {
                    Text("Sharing lets clinics and care team members view your Tidepool data, as on the Share page of Tidepool Web.")
                }

                Section {
                    if devices.isEmpty {
                        if isLoading {
                            HStack { Spacer(); ProgressView(); Spacer() }
                        } else if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                        } else {
                            Text("No devices uploaded in the last 30 days.")
                                .foregroundStyle(.secondary)
                        }
                    }
                    ForEach(devices) { device in
                        NavigationLink(value: SettingsRoute.device(device.id)) {
                            DeviceRow(device: device)
                        }
                    }
                } header: {
                    Text("Devices")
                } footer: {
                    Text("Devices that uploaded to Tidepool in the last 30 days, with their most recent settings.")
                }

                Section("Targets") {
                    LabeledContent("Target range", value: "70–180 mg/dL")
                    LabeledContent("Very low", value: "< 54 mg/dL")
                    LabeledContent("Very high", value: "> 250 mg/dL")
                }

                Section {
                    HStack(spacing: 12) {
                        Image("Logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 56, height: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Blipper")
                                .font(.headline)
                            Text("Version \(Self.versionString)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("Blipper shows your Tidepool CGM data for information only. It is not for treatment decisions.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: SettingsRoute.self) { route in
                switch route {
                case .sharing:
                    ShareView(provider: shareProvider)
                case .device(let id):
                    if let device = devices.first(where: { $0.id == id }) {
                        DeviceDetailView(device: device)
                    }
                }
            }
            .refreshable { await load() }
            .task { await load() }
            .confirmationDialog("Sign out of Tidepool?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive, action: onSignOut)
            } message: {
                Text("Your saved login will be removed from this device.")
            }
        }
    }

    private static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            devices = try await deviceProvider.devices()
            errorMessage = nil
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct DeviceRow: View {
    let device: DeviceInfo

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: device.kindSymbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.displayName)
                if let lastUpload = device.lastUpload {
                    Text("Last upload \(lastUpload, format: .relative(presentation: .named))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Detail

struct DeviceDetailView: View {
    let device: DeviceInfo

    var body: some View {
        Form {
            Section("Device") {
                if let manufacturer = device.manufacturer {
                    LabeledContent("Manufacturer", value: manufacturer)
                }
                if let model = device.model {
                    LabeledContent("Model", value: model)
                }
                if let serial = device.serialNumber {
                    LabeledContent("Serial number", value: serial)
                }
                if let lastUpload = device.lastUpload {
                    LabeledContent("Last upload") {
                        Text(lastUpload, format: .dateTime.year().month().day().hour().minute())
                    }
                }
                if !device.tags.isEmpty {
                    LabeledContent("Data", value: device.tags.joined(separator: ", "))
                }
            }

            if let pump = device.pumpSettings {
                pumpSections(pump)
            }

            if let cgm = device.cgmSettings {
                Section {
                    if let transmitter = cgm.transmitterID {
                        LabeledContent("Transmitter", value: transmitter)
                    }
                    LabeledContent("Low alert", value: cgm.lowAlert.map { "\(Int($0)) mg/dL" } ?? "Off")
                    LabeledContent("High alert", value: cgm.highAlert.map { "\(Int($0)) mg/dL" } ?? "Off")
                } header: {
                    Text("CGM Settings")
                } footer: {
                    Text("As of \(cgm.updated, format: .dateTime.month().day().year())")
                }
            }
        }
        .navigationTitle(device.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func pumpSections(_ pump: PumpSettings) -> some View {
        Section {
            ForEach(pump.activeBasalSchedule) { entry in
                scheduleRow(entry.start, entry.value.formatted(.number.precision(.fractionLength(2))), "U/hr")
            }
            if pump.basalSchedules.count > 1 {
                LabeledContent("Other schedules",
                               value: pump.basalSchedules.keys.filter { $0 != pump.activeSchedule }.sorted().joined(separator: ", "))
                    .font(.footnote)
            }
        } header: {
            Text("Basal Schedule" + (pump.activeSchedule.map { " · \($0)" } ?? ""))
        } footer: {
            Text("As of \(pump.updated, format: .dateTime.month().day().year())")
        }

        if !pump.carbRatios.isEmpty {
            Section("Carb Ratios") {
                ForEach(pump.carbRatios) { entry in
                    scheduleRow(entry.start, entry.value.formatted(.number.precision(.fractionLength(0...1))), "g/U")
                }
            }
        }

        if !pump.insulinSensitivities.isEmpty {
            Section("Insulin Sensitivity") {
                ForEach(pump.insulinSensitivities) { entry in
                    scheduleRow(entry.start, entry.value.formatted(.number.precision(.fractionLength(0))), "mg/dL/U")
                }
            }
        }

        if !pump.targets.isEmpty {
            Section("Correction Targets") {
                ForEach(pump.targets) { entry in
                    scheduleRow(entry.start, entry.label, "mg/dL")
                }
            }
        }
    }

    private func scheduleRow(_ start: TimeInterval, _ value: String, _ unit: String) -> some View {
        HStack {
            Text(Self.clockTime(start))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer()
            Text(value)
                .monospacedDigit()
            Text(unit)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
        }
    }

    private static func clockTime(_ secondsAfterMidnight: TimeInterval) -> String {
        let date = Calendar.current.startOfDay(for: Date()).addingTimeInterval(secondsAfterMidnight)
        return date.formatted(.dateTime.hour().minute())
    }
}

#Preview {
    SettingsView()
}
