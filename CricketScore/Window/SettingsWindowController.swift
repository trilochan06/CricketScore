import AppKit
import SwiftUI

/// A plain AppKit window for Settings, so it opens reliably from the menu bar,
/// the overlay's ⋮ menu, or a relaunch (SwiftUI's Settings scene can't be opened
/// programmatically from AppKit on macOS 14+).
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let settings: AppSettings
    private let viewModel: ScoreViewModel

    init(settings: AppSettings, viewModel: ScoreViewModel) {
        self.settings = settings
        self.viewModel = viewModel
    }

    func show() {
        if window == nil {
            let controller = NSHostingController(rootView: SettingsView(settings: settings, viewModel: viewModel))
            let window = NSWindow(contentViewController: controller)
            window.title = "Cricket Score Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            window.setFrameAutosaveName("CricketScoreSettings")
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
