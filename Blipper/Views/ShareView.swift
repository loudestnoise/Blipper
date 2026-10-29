//
//  ShareView.swift
//  Blipper
//
//  Mirrors the Share page in Tidepool Web: who can see the account's data, pending invites,
//  and the actions on each row (upload permission, resend, revoke, remove).
//

import SwiftUI

struct ShareView: View {
    let provider: any ShareProvider

    @State private var entries: [ShareEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var notice: String?
    @State private var noticeTask: Task<Void, Never>?
    @State private var showInvite = Self.openInviteOnLaunch
    @State private var pendingAction: PendingAction?
    @State private var busyID: String?

    /// `-openShareInvite` presents the invite form at once (Debug builds only).
    private static var openInviteOnLaunch: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-openShareInvite")
        #else
        false
        #endif
    }

    private struct PendingAction: Identifiable {
        enum Kind { case revoke, resend }
        let kind: Kind
        let entry: ShareEntry
        var id: String { "\(kind)-\(entry.id)" }
    }

    private var sharing: [ShareEntry] { entries.filter { !$0.isPending } }
    private var pending: [ShareEntry] { entries.filter(\.isPending) }

    var body: some View {
        Form {
            if let notice {
                Section {
                    Label(notice, systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                }
            }
            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }

            Section {
                if entries.isEmpty, !isLoading, errorMessage == nil {
                    Text("You have not invited anyone to view your data.")
                        .foregroundStyle(.secondary)
                }
                if entries.isEmpty, isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
                ForEach(sharing) { entry in
                    row(entry)
                }
            } header: {
                Text("Sharing")
            } footer: {
                if !sharing.isEmpty {
                    Text("These clinics and care team members can view your Tidepool data.")
                }
            }

            if !pending.isEmpty {
                Section {
                    ForEach(pending) { entry in
                        row(entry)
                    }
                } header: {
                    Text("Invites")
                } footer: {
                    Text("An invite shows here until it is accepted. You can resend a care team invite or revoke any invite.")
                }
            }
        }
        .navigationTitle("Sharing")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Share Data", systemImage: "square.and.arrow.up") { showInvite = true }
            }
        }
        .sheet(isPresented: $showInvite) {
            ShareInviteView(provider: provider, existing: entries) { message in
                show(notice: message)
                Task { await load() }
            }
        }
        .confirmationDialog(
            dialogTitle(for: pendingAction),
            isPresented: Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }),
            titleVisibility: .visible,
            presenting: pendingAction
        ) { action in
            switch action.kind {
            case .revoke:
                Button(revokeButtonTitle(action.entry), role: .destructive) {
                    Task { await revoke(action.entry) }
                }
            case .resend:
                Button("Resend Invite") {
                    Task { await resend(action.entry) }
                }
            }
        } message: { action in
            Text(dialogMessage(for: action))
        }
        .refreshable { await load() }
        .task { await load() }
    }

    // MARK: Rows

    private func row(_ entry: ShareEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry.kind == .clinic ? "building.2" : "person")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayName)
                if entry.name != nil, let email = entry.email {
                    Text(email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Text(entry.kindLabel)
                    Text("·")
                    Text(entry.statusLabel)
                        .foregroundStyle(entry.status == .inviteDeclined ? .red : entry.isPending ? .orange : .green)
                    Text("·")
                    Text(entry.permissions.upload ? "Can upload" : "View only")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if busyID == entry.id {
                ProgressView()
            } else {
                Menu {
                    menuItems(entry)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
                .accessibilityLabel("Actions for \(entry.displayName)")
            }
        }
        .contextMenu { menuItems(entry) }
    }

    @ViewBuilder
    private func menuItems(_ entry: ShareEntry) -> some View {
        if entry.isPending {
            if entry.kind == .member, entry.status != .inviteDeclined {
                Button("Resend Invite", systemImage: "arrow.clockwise") {
                    pendingAction = PendingAction(kind: .resend, entry: entry)
                }
            }
            Button("Revoke Invite", systemImage: "xmark.circle", role: .destructive) {
                pendingAction = PendingAction(kind: .revoke, entry: entry)
            }
        } else {
            Button(
                entry.permissions.upload ? "Remove upload permission" : "Allow upload permission",
                systemImage: entry.permissions.upload ? "icloud.slash" : "icloud.and.arrow.up"
            ) {
                Task { await setUpload(!entry.permissions.upload, for: entry) }
            }
            Button(entry.kind == .clinic ? "Remove Clinic" : "Remove Care Team Member", systemImage: "trash", role: .destructive) {
                pendingAction = PendingAction(kind: .revoke, entry: entry)
            }
        }
    }

    // MARK: Dialog text

    private func dialogTitle(for action: PendingAction?) -> String {
        guard let action else { return "" }
        switch (action.kind, action.entry.isPending, action.entry.kind) {
        case (.resend, _, _): return "Confirm Resending Invite"
        case (.revoke, true, _): return "Revoke Invite?"
        case (.revoke, false, .clinic): return "Leave \(action.entry.displayName)"
        case (.revoke, false, .member): return "Remove \(action.entry.displayName)"
        }
    }

    private func dialogMessage(for action: PendingAction) -> String {
        let name = action.entry.displayName
        switch (action.kind, action.entry.isPending, action.entry.kind) {
        case (.resend, _, _):
            if let created = action.entry.created {
                let date = created.formatted(.dateTime.year().month().day())
                return "You invited \(name) to view your data on \(date). Are you sure you want to resend this invite?"
            }
            return "Are you sure you want to resend this invite to \(name)?"
        case (.revoke, true, _):
            return "Are you sure you want to revoke this share invite to \(name)?"
        case (.revoke, false, .clinic):
            return "\(name) will lose all access to your data. Are you sure you want to leave this clinic?"
        case (.revoke, false, .member):
            return "\(name) will lose all access to your data. Are you sure you want to remove this user from your care team?"
        }
    }

    private func revokeButtonTitle(_ entry: ShareEntry) -> String {
        if entry.isPending { return "Revoke Invite" }
        return entry.kind == .clinic ? "Leave Clinic" : "Remove User"
    }

    // MARK: Actions

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            entries = try await provider.shareEntries()
            errorMessage = nil
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setUpload(_ allowed: Bool, for entry: ShareEntry) async {
        await perform(on: entry) {
            try await provider.setUpload(allowed, for: entry)
            return "Upload permission for \(entry.displayName) has been \(allowed ? "enabled" : "disabled")."
        }
    }

    private func resend(_ entry: ShareEntry) async {
        await perform(on: entry) {
            try await provider.resendInvite(entry)
            return "Share invite to \(entry.displayName) has been resent."
        }
    }

    private func revoke(_ entry: ShareEntry) async {
        await perform(on: entry) {
            try await provider.revoke(entry)
            return entry.isPending
                ? "Share invite to \(entry.displayName) has been revoked."
                : "Share access for \(entry.displayName) has been revoked."
        }
    }

    /// Runs `operation` with the row marked busy, then shows its message and reloads the list.
    private func perform(on entry: ShareEntry, _ operation: () async throws -> String) async {
        busyID = entry.id
        defer { busyID = nil }
        do {
            let message = try await operation()
            errorMessage = nil
            show(notice: message)
            await load()
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func show(notice message: String) {
        notice = message
        noticeTask?.cancel()
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(5))
            if !Task.isCancelled { notice = nil }
        }
    }
}

#Preview {
    NavigationStack {
        ShareView(provider: MockShareProvider())
    }
}
