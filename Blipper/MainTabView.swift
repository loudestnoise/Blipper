//
//  MainTabView.swift
//  Blipper
//

import SwiftUI

struct MainTabView: View {
    enum Tab: String {
        case today, trends, log, notes, settings
    }

    let glucoseProvider: any GlucoseDataProvider
    let therapyProvider: any TherapyDataProvider
    let deviceProvider: any DeviceInfoProvider
    let shareProvider: any ShareProvider
    let dataConnectionProvider: any DataConnectionProvider
    let noteProvider: any NoteProvider
    let email: String?
    /// The live session, for switching accounts; `nil` on mock data.
    let session: SessionStore?
    let onSignOut: () -> Void

    @State private var selection: Tab

    init(
        glucoseProvider: any GlucoseDataProvider = MockGlucoseProvider(),
        therapyProvider: any TherapyDataProvider = MockTherapyProvider(),
        deviceProvider: any DeviceInfoProvider = MockDeviceInfoProvider(),
        shareProvider: any ShareProvider = MockShareProvider(),
        dataConnectionProvider: any DataConnectionProvider = MockDataConnectionProvider(),
        noteProvider: any NoteProvider = MockNoteProvider(),
        email: String? = nil,
        session: SessionStore? = nil,
        onSignOut: @escaping () -> Void = {},
        initialTab: Tab = .today
    ) {
        self.glucoseProvider = glucoseProvider
        self.therapyProvider = therapyProvider
        self.deviceProvider = deviceProvider
        self.shareProvider = shareProvider
        self.dataConnectionProvider = dataConnectionProvider
        self.noteProvider = noteProvider
        self.email = email
        self.session = session
        self.onSignOut = onSignOut
        _selection = State(initialValue: initialTab)
    }

    var body: some View {
        TabView(selection: $selection) {
            ContentView(
                provider: glucoseProvider, therapyProvider: therapyProvider,
                sharedAccountName: sharedAccountName,
                switchTitle: session?.account?.isClinicPatient == true ? "Patients" : "Switch Account",
                onSwitchAccount: session.map { session in { session.leaveAccount() } }
            )
                .tabItem { Label("Today", systemImage: "waveform.path.ecg") }
                .tag(Tab.today)

            TrendsView(provider: glucoseProvider)
                .tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }
                .tag(Tab.trends)

            BGLogView(provider: therapyProvider)
                .tabItem { Label("BG Log", systemImage: "drop") }
                .tag(Tab.log)

            NotesView(
                provider: noteProvider, glucoseProvider: glucoseProvider, therapyProvider: therapyProvider,
                canAdd: session?.account?.isClinicPatient != true
            )
                .tabItem { Label("Notes", systemImage: "note.text") }
                .tag(Tab.notes)

            SettingsView(
                email: email,
                session: session,
                deviceProvider: deviceProvider,
                shareProvider: shareProvider,
                dataConnectionProvider: dataConnectionProvider,
                onSignOut: onSignOut
            )
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .modifier(MinimizingTabBar())
    }

    /// Whose data this is, when it is not the login's own.
    private var sharedAccountName: String? {
        guard let account = session?.account, !account.isOwn else { return nil }
        return account.name
    }
}

/// Tucks the tab bar away while scrolling down; a no-op before iOS 26.
private struct MinimizingTabBar: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.tabBarMinimizeBehavior(.onScrollDown)
        } else {
            content
        }
    }
}

#Preview {
    MainTabView()
}
