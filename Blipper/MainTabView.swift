//
//  MainTabView.swift
//  Blipper
//

import SwiftUI

struct MainTabView: View {
    enum Tab: String {
        case today, trends, settings
    }

    let glucoseProvider: any GlucoseDataProvider
    let deviceProvider: any DeviceInfoProvider
    let email: String?
    let onSignOut: () -> Void

    @State private var selection: Tab

    init(
        glucoseProvider: any GlucoseDataProvider = MockGlucoseProvider(),
        deviceProvider: any DeviceInfoProvider = MockDeviceInfoProvider(),
        email: String? = nil,
        onSignOut: @escaping () -> Void = {},
        initialTab: Tab = .today
    ) {
        self.glucoseProvider = glucoseProvider
        self.deviceProvider = deviceProvider
        self.email = email
        self.onSignOut = onSignOut
        _selection = State(initialValue: initialTab)
    }

    var body: some View {
        TabView(selection: $selection) {
            ContentView(provider: glucoseProvider)
                .tabItem { Label("Today", systemImage: "waveform.path.ecg") }
                .tag(Tab.today)

            TrendsView(provider: glucoseProvider)
                .tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }
                .tag(Tab.trends)

            SettingsView(email: email, deviceProvider: deviceProvider, onSignOut: onSignOut)
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .modifier(MinimizingTabBar())
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
