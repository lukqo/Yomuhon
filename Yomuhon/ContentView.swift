//
//  ContentView.swift
//  Yomuhon
//

import SwiftUI

#if os(macOS)
import AppKit
#endif

struct ContentView: View {
    @AppStorage(AppTheme.storageKey) private var selectedThemeID = YomuhonThemeID.defaultValue.rawValue
    @AppStorage("yomuhon.hasCompletedOnboarding") private var hasCompletedOnboarding = false
    // This object intentionally lives at app level. Source recovery must start
    // on launch, not only after the user opens Settings > Sources.
    @StateObject private var sourceMaintenance: SourcesViewModel

    init() {
        #if DEBUG
        let maintenanceStore: SourceSettingsStoring = Self.isUITesting
            ? YomuhonUITestSourceSettingsStore()
            : SourceSettingsStore.shared
        #else
        let maintenanceStore: SourceSettingsStoring = SourceSettingsStore.shared
        #endif
        _sourceMaintenance = StateObject(wrappedValue: SourcesViewModel(store: maintenanceStore))
    }

    var body: some View {
        ZStack {
            RootView(compositionRoot: .application)

            if !hasCompletedOnboarding && !isUITesting {
                OnboardingView {
                    withAnimation(activeTheme.animation) { hasCompletedOnboarding = true }
                }
                .transition(.opacity)
            }
        }
        .environment(\.yomuhonTheme, activeTheme)
        .preferredColorScheme(activeTheme.id == .ink ? .dark : .light)
        .animation(activeTheme.animation, value: selectedThemeID)
        .animation(activeTheme.animation, value: hasCompletedOnboarding)
        .onAppear {
            if !isUITesting {
                sourceMaintenance.performScheduledMaintenanceIfNeeded()
            }
            configureMacWindowIfNeeded()
        }
    }

    private var activeTheme: YomuhonTheme {
        AppTheme.theme(for: selectedThemeID)
    }

    private static var isUITesting: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-ui-testing")
        #else
        false
        #endif
    }

    private var isUITesting: Bool {
        Self.isUITesting
    }

    private func configureMacWindowIfNeeded() {
        #if os(macOS)
        DispatchQueue.main.async {
            guard let window = NSApplication.shared.windows.first(where: { $0.isVisible }) else {
                return
            }

            // Never force the window to the full visible screen. macOS remembers
            // the user's frame and the window must remain freely resizable.
            window.collectionBehavior.insert(.fullScreenPrimary)
        }
        #endif
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
