import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings: AppSettings
    let viewModel: ScoreViewModel
    let updates: UpdateChecker
    private(set) lazy var actions = AppActions(
        openSettings: { [weak self] in self?.openSettings() },
        quit: { NSApp.terminate(nil) }
    )

    private var overlay: OverlayController?
    private lazy var settingsWindow = SettingsWindowController(settings: settings, viewModel: viewModel)

    override init() {
        settings = AppSettings()
        viewModel = ScoreViewModel(settings: settings)
        let settings = self.settings
        updates = UpdateChecker(serverURL: { settings.resolvedServerURL })
        super.init()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Menu-bar utility: no Dock icon, not in Cmd+Tab (LSUIElement does the same for the bundle).
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if let dir = SnapshotRenderer.outputDirectory {
            viewModel.start()
            Task { await SnapshotRenderer.run(viewModel: viewModel, actions: actions, to: dir) }
            return
        }
        #endif
        guard !terminateIfAlreadyRunning() else { return }

        observeContinuously { [weak self] in self?.applyAppearance() }
        observeContinuously { [weak self] in
            guard let self else { return }
            self.viewModel.setRefreshInterval(self.settings.refreshInterval)
        }

        // Exactly one overlay window for the app's lifetime.
        if overlay == nil {
            overlay = OverlayController(viewModel: viewModel, settings: settings, actions: actions)
        }
        viewModel.start()
        updates.start()

        #if DEBUG
        if OverlaySelfTest.isEnabled {
            Task { await OverlaySelfTest.run(viewModel: viewModel, settings: settings) }
        }
        #endif
    }

    /// Launching the app again (Finder, Spotlight, Login Items) opens Settings — the way back
    /// if both the overlay and the menu-bar icon are hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel.stop()
    }

    func openSettings() {
        settingsWindow.show()
    }

    private func applyAppearance() {
        switch settings.appearance {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    private func terminateIfAlreadyRunning() -> Bool {
        guard let id = Bundle.main.bundleIdentifier else { return false }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .filter { $0 != NSRunningApplication.current }
        guard let existing = others.first else { return false }
        existing.activate()
        NSApp.terminate(nil)
        return true
    }
}
