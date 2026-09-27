import SwiftUI

@main
struct CricketScoreApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra(isInserted: Binding(
            get: { appDelegate.settings.showMenuBarIcon },
            set: { appDelegate.settings.showMenuBarIcon = $0 })
        ) {
            MenuBarView(viewModel: appDelegate.viewModel, settings: appDelegate.settings, updates: appDelegate.updates, actions: appDelegate.actions)
        } label: {
            Image(systemName: "cricket.ball.fill")
                .accessibilityLabel("Cricket Score")
        }
        .menuBarExtraStyle(.window)
    }
}

/// Commands the views can trigger without knowing about AppKit.
struct AppActions {
    var openSettings: () -> Void
    var quit: () -> Void
}
