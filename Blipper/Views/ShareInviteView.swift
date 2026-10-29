//
//  ShareInviteView.swift
//  Blipper
//
//  The "Share your data" form from Tidepool Web: a clinic share code that is looked up and
//  confirmed by name before the invite is sent, or a care team member's email address.
//

import SwiftUI

struct ShareInviteView: View {
    let provider: any ShareProvider
    /// Current rows, used to refuse a code or email that is already shared with or invited.
    let existing: [ShareEntry]
    /// Called with the confirmation message after an invite is sent.
    let onSent: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    private enum Mode: String, CaseIterable, Identifiable {
        case clinic = "Clinic"
        case member = "Care Team Member"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .clinic
    @State private var shareCode = ""
    @State private var clinic: ClinicSummary?
    @State private var email = ""
    @State private var allowUpload = true
    @State private var isWorking = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Share with", selection: $mode) {
                        ForEach(Mode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(isWorking)
                }

                switch mode {
                case .clinic: clinicSections
                case .member: memberSections
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button(action: submit) {
                        HStack {
                            Spacer()
                            if isWorking {
                                ProgressView()
                            } else {
                                Text(submitTitle)
                            }
                            Spacer()
                        }
                    }
                    .disabled(isWorking || !canSubmit)
                }
            }
            .navigationTitle("Share your data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if mode == .clinic, clinic != nil {
                        Button("Back") { clearLookup() }
                    } else {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            .onChange(of: mode) { errorMessage = nil }
            .onAppear { focused = true }
        }
    }

    // MARK: Clinic

    @ViewBuilder
    private var clinicSections: some View {
        if let clinic {
            Section {
                LabeledContent("Clinic Name", value: clinic.name)
                Toggle("Allow upload of data", isOn: $allowUpload)
            } footer: {
                Text("If the Clinic Name is incorrect, go back and check the 12 digit share code you entered.")
            }
        } else {
            Section {
                TextField("Enter share code", text: $shareCode)
                    .font(.body.monospaced())
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .focused($focused)
                    .submitLabel(.go)
                    .onSubmit(submit)
                    .onChange(of: shareCode) { _, newValue in
                        let formatted = ShareCode.format(newValue)
                        if formatted != newValue { shareCode = formatted }
                        errorMessage = nil
                    }
            } footer: {
                Text("Enter the 12 digit Clinic share code provided to you.")
            }
        }
    }

    // MARK: Member

    @ViewBuilder
    private var memberSections: some View {
        Section {
            TextField("Enter email address", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focused)
                .submitLabel(.go)
                .onSubmit(submit)
                .onChange(of: email) { errorMessage = nil }
            Toggle("Allow upload of data", isOn: $allowUpload)
        } footer: {
            Text("Enter the email address of the new care team member.")
        }
    }

    // MARK: Submit

    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSubmit: Bool {
        switch mode {
        case .clinic: clinic != nil || ShareCode.isComplete(shareCode)
        case .member: Self.looksLikeEmail(trimmedEmail)
        }
    }

    private var submitTitle: String {
        switch mode {
        case .clinic: clinic == nil ? "Submit Code" : "Send Invite"
        case .member: "Invite Member"
        }
    }

    private func submit() {
        guard canSubmit, !isWorking else { return }
        Task { await perform() }
    }

    private func perform() async {
        isWorking = true
        defer { isWorking = false }
        errorMessage = nil
        do {
            switch mode {
            case .clinic where clinic == nil:
                let found = try await provider.clinic(shareCode: shareCode)
                guard !existing.contains(where: { $0.kind == .clinic && ($0.id == found.id || $0.clinicID == found.id) }) else {
                    throw ShareError.alreadySharing
                }
                clinic = found
                focused = false
            case .clinic:
                guard let clinic else { return }
                try await provider.inviteClinic(shareCode: clinic.shareCode, permissions: SharePermissions(upload: allowUpload))
                onSent("Share invite to \(clinic.name) has been sent.")
                dismiss()
            case .member:
                let address = trimmedEmail
                guard !existing.contains(where: { $0.email?.lowercased() == address.lowercased() }) else {
                    throw ShareError.rejected("You are already sharing with this care team member. Please enter a new email.")
                }
                try await provider.inviteMember(email: address, permissions: SharePermissions(upload: allowUpload))
                onSent("Share invite to \(address) has been sent.")
                dismiss()
            }
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func clearLookup() {
        clinic = nil
        errorMessage = nil
        focused = true
    }

    private static func looksLikeEmail(_ text: String) -> Bool {
        let parts = text.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".") && !parts[1].hasSuffix(".")
    }
}

#Preview {
    ShareInviteView(provider: MockShareProvider(), existing: []) { _ in }
}
