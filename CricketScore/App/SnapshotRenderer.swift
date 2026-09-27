import AppKit
import SwiftUI

#if DEBUG

/// Development aid: renders the real overlay views to PNGs for every state.
///     CRICKETSCORE_SNAPSHOT_DIR=/tmp/shots .build/debug/CricketScore
@MainActor
enum SnapshotRenderer {
    static var outputDirectory: URL? {
        ProcessInfo.processInfo.environment["CRICKETSCORE_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
    }

    static func run(viewModel: ScoreViewModel, actions: AppActions, to dir: URL) async {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let scenarios: [MockScenario] = [.live, .inningsBreak, .rainDelay, .upcoming, .completed, .noLiveMatches, .apiError]
        for scenario in scenarios {
            viewModel.setMockScenario(scenario)
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            for notch in [true, false] {
                for expanded in [false, true] {
                    for dark in notch ? [true] : [false, true] {
                        let layout = OverlayLayout()
                        layout.style = notch ? .notch(width: 179, height: 32) : .floating
                        viewModel.isExpanded = expanded
                        let view = ScoreOverlayWidget(viewModel: viewModel, layout: layout, actions: actions)
                            .environment(\.isSnapshot, true)
                            .environment(\.colorScheme, notch || dark ? .dark : .light)
                            .padding(20)
                            .background(dark || notch ? Color(white: 0.28) : Color(white: 0.9))
                        let renderer = ImageRenderer(content: view)
                        renderer.scale = 2
                        guard let image = renderer.cgImage else { continue }
                        let rep = NSBitmapImageRep(cgImage: image)
                        let name = "\(scenario.rawValue)-\(notch ? "notch" : "floating")-\(expanded ? "expanded" : "collapsed")\(notch ? "" : dark ? "-dark" : "-light").png"
                        try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(name))
                    }
                }
            }
        }
        viewModel.isExpanded = false
        NSApp.terminate(nil)
    }
}

/// Development aid: drives the real panel through its states and logs the window frame.
///     CRICKETSCORE_SELFTEST=1 .build/debug/CricketScore
@MainActor
enum OverlaySelfTest {
    static var isEnabled: Bool { ProcessInfo.processInfo.environment["CRICKETSCORE_SELFTEST"] != nil }

    static func run(viewModel: ScoreViewModel, settings: AppSettings) async {
        func frame() -> String {
            let pid = ProcessInfo.processInfo.processIdentifier
            let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
            let mine = list.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid && ($0[kCGWindowLayer as String] as? Int) == 25 }
            guard let b = mine.first?[kCGWindowBounds as String] as? [String: Double] else { return "hidden" }
            return "x=\(Int(b["X"]!)) y=\(Int(b["Y"]!)) w=\(Int(b["Width"]!)) h=\(Int(b["Height"]!)) windows=\(mine.count)"
        }
        func step(_ name: String, wait: Double = 1.2, _ action: () -> Void) async {
            action()
            try? await Task.sleep(nanoseconds: UInt64(wait * 1e9))
            print("[selftest] \(name.padding(toLength: 34, withPad: " ", startingAt: 0)) \(frame())  key=\(NSApp.keyWindow != nil) active=\(NSApp.isActive)")
        }
        let original = (settings.position, settings.hideWhenNoLiveMatches)
        await step("launch (collapsed, notch)", wait: 3) {}
        await step("expand") { viewModel.isExpanded = true }
        await step("collapse") { viewModel.isExpanded = false }
        await step("position: top right") { settings.position = .topRight }
        await step("expand at top right") { viewModel.isExpanded = true }
        await step("collapse") { viewModel.isExpanded = false }
        await step("position: below notch") { settings.position = .belowNotch }
        await step("scenario: rain delay", wait: 2) { viewModel.setMockScenario(.rainDelay) }
        await step("scenario: nothing scheduled (hide)", wait: 2) { viewModel.setMockScenario(.nothingScheduled) }
        await step("hideWhenNoLive off", wait: 1) { settings.hideWhenNoLiveMatches = false }
        await step("scenario: offline", wait: 2) { viewModel.setMockScenario(.offline) }
        await step("scenario: live again", wait: 2) { viewModel.setMockScenario(.live) }
        await step("pause overlay") { viewModel.pauseOverlay() }
        await step("show overlay") { viewModel.showOverlay() }
        await step("position: top center") { settings.position = original.0; settings.hideWhenNoLiveMatches = original.1 }
        print("[selftest] done")
        NSApp.terminate(nil)
    }
}
#endif

private struct IsSnapshotKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// ImageRenderer can't draw NSVisualEffectView, so snapshots use a flat stand-in.
    var isSnapshot: Bool {
        get { self[IsSnapshotKey.self] }
        set { self[IsSnapshotKey.self] = newValue }
    }
}
