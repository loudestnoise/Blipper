//
//  PatientListView.swift
//  Blipper
//
//  A clinic's patients, for a clinician to pick whose data to view. Searching and paging happen
//  on the server, so a large clinic is never downloaded whole.
//

import SwiftUI

struct PatientListView: View {
    let session: SessionStore
    let clinic: ClinicSummary

    @State private var patients: [ClinicPatient] = []
    @State private var matching = 0
    @State private var query = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    private static let pageSize = 50

    var body: some View {
        List {
            if patients.isEmpty {
                Section {
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    } else if isLoading {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    } else {
                        Text(query.isEmpty ? "This clinic has no patients." : "No patients match “\(query)”.")
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Section {
                    ForEach(patients) { patient in
                        Button {
                            session.select(patient, in: clinic)
                        } label: {
                            PatientRow(patient: patient, isCurrent: patient.id == session.account?.id)
                        }
                        .tint(.primary)
                    }
                    if patients.count < matching {
                        HStack { Spacer(); ProgressView(); Spacer() }
                            .task { await loadMore() }
                    }
                } footer: {
                    Text(matching == 1 ? "1 patient" : "\(matching) patients")
                }
            }
        }
        .navigationTitle(clinic.name)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Name, MRN, or DOB")
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        // Restarts on every keystroke; the pause keeps a typed word from becoming a request per letter.
        .task(id: query) {
            if !query.isEmpty {
                try? await Task.sleep(for: .milliseconds(300))
                if Task.isCancelled { return }
            }
            await reload()
        }
        .refreshable { await reload() }
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        let asked = query
        do {
            let page = try await session.patients(in: clinic, search: Self.searchTerm(asked), offset: 0, limit: Self.pageSize)
            guard asked == query else { return }
            patients = page.patients
            matching = page.matching
            errorMessage = nil
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            patients = []
            matching = 0
            errorMessage = error.localizedDescription
        }
    }

    private func loadMore() async {
        let asked = query
        let offset = patients.count
        do {
            let page = try await session.patients(in: clinic, search: Self.searchTerm(asked), offset: offset, limit: Self.pageSize)
            guard asked == query, offset == patients.count else { return }
            let known = Set(patients.map(\.id))
            patients += page.patients.filter { !known.contains($0.id) }
            // An empty page means the list shrank underneath us; stop asking for more.
            matching = page.patients.isEmpty ? patients.count : page.matching
        } catch {
            matching = patients.count
        }
    }

    /// The server matches birth dates only as `yyyy-MM-dd`, so a date typed `M/D/YYYY` is rewritten.
    static func searchTerm(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let month = Int(parts[0]), let day = Int(parts[1]), let year = Int(parts[2]),
              (1...12).contains(month), (1...31).contains(day), parts[2].count == 4 else { return trimmed }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}

private struct PatientRow: View {
    let patient: ClinicPatient
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(patient.fullName)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            if isCurrent {
                Image(systemName: "checkmark")
                    .fontWeight(.semibold)
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Current")
            }
        }
        .contentShape(Rectangle())
    }

    private var detail: String {
        [patient.birthDate.map { "DOB \($0)" }, patient.mrn.map { "MRN \($0)" }]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}
