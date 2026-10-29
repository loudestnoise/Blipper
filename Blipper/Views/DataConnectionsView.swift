//
//  DataConnectionsView.swift
//  Blipper
//
//  Mirrors the Data Connections dialog in Tidepool Web: one row per cloud provider with its
//  logo, connection status, and a Connect, Reconnect, or Disconnect action. The provider's own
//  sign-in runs in an in-app Safari sheet; when it closes, the status is fetched again.
//

import SafariServices
import SwiftUI

struct DataConnectionsView: View {
    let provider: any DataConnectionProvider

    @State private var sources: [DataSource] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var notice: String?
    @State private var noticeTask: Task<Void, Never>?
    @State private var busy: DataProvider?
    @State private var authorization: Authorization?
    /// Kept across the sheet's dismissal, since `authorization` is cleared when it closes.
    @State private var lastAuthorization: Authorization?
    @State private var confirmDisconnect: DataProvider?
    @State private var followUp: FollowUp?

    private struct Authorization: Identifiable {
        let provider: DataProvider
        let url: URL
        /// Whether the provider counted as connected before the sign-in started.
        let wasConnected: Bool
        var id: DataProvider { provider }
    }

    private struct FollowUp: Identifiable {
        let title: String
        let message: String
        var id: String { title }
    }

    private var connections: [DataConnection] {
        DataProvider.allCases.map { DataConnection(provider: $0, source: DataConnection.current(for: $0, in: sources)) }
    }

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
                ForEach(connections) { connection in
                    row(connection)
                }
            } header: {
                Text("Data Connections")
            } footer: {
                Text("Connecting lets Tidepool pull data from the provider's cloud on your behalf. You sign in on the provider's own site; when you see \"Connection Authorized\", tap Done to come back.")
            }
        }
        .navigationTitle("Data Connections")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if sources.isEmpty, isLoading {
                ProgressView()
            }
        }
        .sheet(item: $authorization, onDismiss: { Task { await finishAuthorization() } }) { authorization in
            SafariView(url: authorization.url) { self.authorization = nil }
                .ignoresSafeArea()
        }
        .confirmationDialog(
            "Disconnect \(confirmDisconnect?.displayName ?? "")?",
            isPresented: Binding(get: { confirmDisconnect != nil }, set: { if !$0 { confirmDisconnect = nil } }),
            titleVisibility: .visible,
            presenting: confirmDisconnect
        ) { provider in
            Button("Disconnect", role: .destructive) {
                Task { await disconnect(provider) }
            }
        } message: { provider in
            Text("Tidepool will stop collecting new data from \(provider.displayName).")
        }
        .alert(item: $followUp) { followUp in
            Alert(title: Text(followUp.title), message: Text(followUp.message), dismissButton: .default(Text("Done")))
        }
        .refreshable { await load() }
        .task { await load() }
    }

    // MARK: Rows

    private func row(_ connection: DataConnection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                ProviderLogo(provider: connection.provider)
                VStack(alignment: .leading, spacing: 2) {
                    Text(connection.provider.displayName)
                        .font(.headline)
                    HStack(spacing: 4) {
                        Image(systemName: statusSymbol(connection.status))
                        Text(connection.statusText)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(statusColor(connection.status))
                    if let message = connection.message() {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            if busy == connection.provider {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if !connection.actions.isEmpty {
                HStack {
                    ForEach(connection.actions, id: \.self) { action in
                        actionButton(action, for: connection.provider)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func actionButton(_ action: DataConnection.Action, for provider: DataProvider) -> some View {
        switch action {
        case .connect:
            Button("Connect") { Task { await connect(provider) } }
                .buttonStyle(.borderedProminent)
        case .reconnect:
            Button("Reconnect") { Task { await connect(provider) } }
                .buttonStyle(.borderedProminent)
        case .disconnect:
            Button("Disconnect", role: .destructive) { confirmDisconnect = provider }
                .buttonStyle(.bordered)
        }
    }

    private func statusSymbol(_ status: DataConnection.Status) -> String {
        switch status {
        case .connected: "checkmark.circle.fill"
        case .error: "exclamationmark.circle.fill"
        case .disconnected, .notConnected: "circle.dashed"
        }
    }

    private func statusColor(_ status: DataConnection.Status) -> Color {
        switch status {
        case .connected: .green
        case .error: .red
        case .disconnected, .notConnected: .secondary
        }
    }

    // MARK: Actions

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            sources = try await provider.dataSources()
            errorMessage = nil
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func connect(_ dataProvider: DataProvider) async {
        busy = dataProvider
        defer { busy = nil }
        do {
            let url = try await provider.authorizationURL(for: dataProvider)
            errorMessage = nil
            let current = DataConnection.current(for: dataProvider, in: sources)
            let started = Authorization(provider: dataProvider, url: url, wasConnected: current?.state == .connected)
            lastAuthorization = started
            authorization = started
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// After the sign-in sheet closes, re-reads the data sources and reports what changed.
    private func finishAuthorization() async {
        guard let finished = lastAuthorization else { return }
        lastAuthorization = nil
        await load()
        let now = DataConnection.current(for: finished.provider, in: sources)
        if now?.state == .connected, !finished.wasConnected {
            show(notice: "Connection Authorized. Thank you for connecting \(finished.provider.displayName)!")
        } else if now?.state == .connected {
            show(notice: "\(finished.provider.displayName) is connected.")
        } else {
            show(notice: "No new \(finished.provider.displayName) connection was made. You can always connect later.")
        }
    }

    private func disconnect(_ dataProvider: DataProvider) async {
        busy = dataProvider
        defer { busy = nil }
        do {
            try await provider.disconnect(dataProvider)
            errorMessage = nil
            await load()
            show(notice: "\(dataProvider.displayName) has been disconnected.")
            if let instructions = dataProvider.disconnectInstructions {
                followUp = FollowUp(title: instructions.title, message: instructions.message)
            }
        } catch is CancellationError {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func show(notice message: String) {
        notice = message
        noticeTask?.cancel()
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(6))
            if !Task.isCancelled { notice = nil }
        }
    }
}

// MARK: - Logo

/// A provider's logo on a white card, so brand colors read the same in light and dark mode.
private struct ProviderLogo: View {
    let provider: DataProvider

    var body: some View {
        Image(provider.logoAsset)
            .resizable()
            .scaledToFit()
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(width: 112, height: 44)
            .background(.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.quaternary))
            .accessibilityLabel("\(provider.displayName) logo")
    }
}

// MARK: - Safari

/// In-app Safari for the provider's sign-in. Shares AutoFill with Safari and keeps the user in Blipper.
private struct SafariView: UIViewControllerRepresentable {
    let url: URL
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.barCollapsingEnabled = false
        let controller = SFSafariViewController(url: url, configuration: configuration)
        controller.delegate = context.coordinator
        controller.dismissButtonStyle = .done
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}

    final class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            onFinish()
        }
    }
}

#Preview {
    NavigationStack {
        DataConnectionsView(provider: MockDataConnectionProvider())
    }
}
