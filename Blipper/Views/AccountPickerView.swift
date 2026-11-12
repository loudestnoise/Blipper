//
//  AccountPickerView.swift
//  Blipper
//
//  Choosing which Tidepool account to view when the login has others shared with it:
//  `AccountPickerView` asks after sign-in, `AccountSwitcherView` is the Settings screen.
//

import SwiftUI

/// Shown after sign-in (and at launch, when no default is set) if other accounts are shared with the login.
struct AccountPickerView: View {
    let session: SessionStore

    @State private var makeDefault = true
    /// Starts on the patient list the user just came back from, if any.
    @State private var path: [ClinicSummary]

    init(session: SessionStore) {
        self.session = session
        _path = State(initialValue: session.lastClinic.map { [$0] } ?? [])
    }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                if session.accounts.isEmpty || !session.hasAccountChoice {
                    Section {
                        if let error = session.accountsError {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                            Button("Try Again") { Task { await session.refreshAccounts() } }
                        } else {
                            HStack { Spacer(); ProgressView(); Spacer() }
                        }
                    }
                } else {
                    Section {
                        ForEach(session.accounts) { account in
                            Button {
                                session.select(account, makeDefault: makeDefault)
                            } label: {
                                AccountRow(account: account, isCurrent: false)
                            }
                            .tint(.primary)
                        }
                        Toggle("Open this account by default", isOn: $makeDefault)
                    } header: {
                        Text("Whose data do you want to see?")
                    } footer: {
                        Text(makeDefault
                             ? "Blipper will open the account you pick every time. You can switch to another account in Settings."
                             : "Blipper will ask each time it opens. You can switch to another account in Settings.")
                    }

                    ClinicsSection(session: session, pushesByValue: true)
                }

                Section {
                    Button("Sign Out", role: .destructive, action: session.signOut)
                }
            }
            .navigationTitle("Choose Account")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: ClinicSummary.self) { clinic in
                PatientListView(session: session, clinic: clinic)
            }
        }
    }
}

/// Settings → Viewing: switch between the login's own account and those shared with it.
struct AccountSwitcherView: View {
    let session: SessionStore

    var body: some View {
        Form {
            Section {
                ForEach(session.accounts) { account in
                    Button {
                        if account.id != session.account?.id { session.select(account) }
                    } label: {
                        AccountRow(account: account, isCurrent: account.id == session.account?.id)
                    }
                    .tint(.primary)
                }
            } footer: {
                Text("Switching shows that account's data throughout Blipper.")
            }

            ClinicsSection(session: session)

            if let current = session.account, !current.isClinicPatient {
                Section {
                    Toggle("Open \(current.isOwn ? "my account" : current.name) by default", isOn: Binding(
                        get: { session.defaultAccount?.id == current.id },
                        set: { session.setDefault($0 ? current : nil) }
                    ))
                } footer: {
                    Text(defaultFooter(current: current))
                }
            }
        }
        .navigationTitle("Viewing")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await session.refreshAccounts() }
    }

    private func defaultFooter(current: ViewableAccount) -> String {
        guard let preferred = session.defaultAccount else {
            return "Blipper asks which account to open each time it starts."
        }
        if preferred.id == current.id {
            return "Blipper opens this account each time it starts."
        }
        return "Blipper currently opens \(preferred.isOwn ? "your account" : preferred.name) each time it starts."
    }
}

/// Clinics the login works in; each opens its patient list.
private struct ClinicsSection: View {
    let session: SessionStore
    /// The picker's own stack takes clinics as values; inside Settings' stack the link carries its destination.
    var pushesByValue = false

    var body: some View {
        if !session.clinics.isEmpty {
            Section {
                ForEach(session.clinics) { clinic in
                    if pushesByValue {
                        NavigationLink(value: clinic) {
                            Label(clinic.name, systemImage: "cross.case")
                        }
                    } else {
                        NavigationLink {
                            PatientListView(session: session, clinic: clinic)
                        } label: {
                            Label(clinic.name, systemImage: "cross.case")
                        }
                    }
                }
            } header: {
                Text("Clinic patients")
            } footer: {
                Text("Pick a clinic, then a patient. Patients are not remembered: Blipper asks again each time it opens.")
            }
        }
    }
}

private struct AccountRow: View {
    let account: ViewableAccount
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: account.isOwn ? "person.crop.circle" : "person.2.circle")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                Text(account.isOwn ? "My account" : "Shared with me")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
}
