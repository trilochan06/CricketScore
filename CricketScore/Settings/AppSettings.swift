import Foundation
import Observation

enum OverlayPosition: String, CaseIterable, Identifiable {
    case topCenter, topRight, belowNotch

    var id: String { rawValue }
    var title: String {
        switch self {
        case .topCenter: "Top Center"
        case .topRight: "Top Right"
        case .belowNotch: "Below Notch"
        }
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// User preferences, persisted in UserDefaults. Observable so both SwiftUI and
/// the AppKit window controller react to changes immediately.
@MainActor
@Observable
final class AppSettings {
    private enum Key {
        static let showOverlay = "showOverlay"
        static let showMenuBarIcon = "showMenuBarIcon"
        static let position = "overlayPosition"
        static let allowDragging = "allowDragging"
        static let customAnchor = "customOverlayAnchor"
        static let appearance = "appearance"
        static let refreshInterval = "refreshInterval"
        static let autoShowOnMatchStart = "autoShowOnMatchStart"
        static let hideWhenNoLiveMatches = "hideWhenNoLiveMatches"
        static let rememberSelectedMatch = "rememberSelectedMatch"
        static let savedMatchID = "savedMatchID"
        static let dataSource = "dataSource"
        static let serverURL = "serverURL"
    }

    /// Where the Cricket Live server runs. Override with the CRICKET_SERVER_URL environment variable.
    nonisolated static let defaultServerURL: URL = {
        if let env = ProcessInfo.processInfo.environment["CRICKET_SERVER_URL"], let url = URL(string: env) { return url }
        return URL(string: "http://localhost:8787")!
    }()

    static let refreshOptions = [15, 30, 60]

    @ObservationIgnored private let defaults: UserDefaults

    var showOverlay: Bool { didSet { defaults.set(showOverlay, forKey: Key.showOverlay) } }
    var showMenuBarIcon: Bool { didSet { defaults.set(showMenuBarIcon, forKey: Key.showMenuBarIcon) } }
    var position: OverlayPosition { didSet { defaults.set(position.rawValue, forKey: Key.position) } }
    var allowDragging: Bool { didSet { defaults.set(allowDragging, forKey: Key.allowDragging) } }
    /// Top-center point of a dragged widget, in global screen coordinates.
    var customAnchor: CGPoint? {
        didSet {
            if let p = customAnchor { defaults.set([p.x, p.y], forKey: Key.customAnchor) }
            else { defaults.removeObject(forKey: Key.customAnchor) }
        }
    }
    var appearance: AppearanceMode { didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) } }
    var refreshInterval: Int { didSet { defaults.set(refreshInterval, forKey: Key.refreshInterval) } }
    var autoShowOnMatchStart: Bool { didSet { defaults.set(autoShowOnMatchStart, forKey: Key.autoShowOnMatchStart) } }
    var hideWhenNoLiveMatches: Bool { didSet { defaults.set(hideWhenNoLiveMatches, forKey: Key.hideWhenNoLiveMatches) } }
    var rememberSelectedMatch: Bool {
        didSet {
            defaults.set(rememberSelectedMatch, forKey: Key.rememberSelectedMatch)
            if !rememberSelectedMatch { savedMatchID = nil }
        }
    }
    var savedMatchID: String? { didSet { defaults.set(savedMatchID, forKey: Key.savedMatchID) } }
    var dataSource: DataSource { didSet { defaults.set(dataSource.rawValue, forKey: Key.dataSource) } }
    var serverURL: String { didSet { defaults.set(serverURL, forKey: Key.serverURL) } }

    /// The configured server URL, or the default if the field is empty/invalid.
    var resolvedServerURL: URL {
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme, ["http", "https"].contains(scheme), url.host != nil else {
            return Self.defaultServerURL
        }
        return url
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.showOverlay: true,
            Key.showMenuBarIcon: true,
            Key.position: OverlayPosition.topCenter.rawValue,
            Key.allowDragging: false,
            Key.appearance: AppearanceMode.system.rawValue,
            Key.refreshInterval: 30,
            Key.autoShowOnMatchStart: true,
            Key.hideWhenNoLiveMatches: true,
            Key.rememberSelectedMatch: true,
            Key.dataSource: DataSource.liveServer.rawValue,
            Key.serverURL: Self.defaultServerURL.absoluteString,
        ])
        showOverlay = defaults.bool(forKey: Key.showOverlay)
        showMenuBarIcon = defaults.bool(forKey: Key.showMenuBarIcon)
        position = OverlayPosition(rawValue: defaults.string(forKey: Key.position) ?? "") ?? .topCenter
        allowDragging = defaults.bool(forKey: Key.allowDragging)
        if let xy = defaults.array(forKey: Key.customAnchor) as? [Double], xy.count == 2 {
            customAnchor = CGPoint(x: xy[0], y: xy[1])
        } else {
            customAnchor = nil
        }
        appearance = AppearanceMode(rawValue: defaults.string(forKey: Key.appearance) ?? "") ?? .system
        let interval = defaults.integer(forKey: Key.refreshInterval)
        refreshInterval = Self.refreshOptions.contains(interval) ? interval : 30
        autoShowOnMatchStart = defaults.bool(forKey: Key.autoShowOnMatchStart)
        hideWhenNoLiveMatches = defaults.bool(forKey: Key.hideWhenNoLiveMatches)
        rememberSelectedMatch = defaults.bool(forKey: Key.rememberSelectedMatch)
        savedMatchID = defaults.string(forKey: Key.savedMatchID)
        dataSource = DataSource(rawValue: defaults.string(forKey: Key.dataSource) ?? "") ?? .liveServer
        serverURL = defaults.string(forKey: Key.serverURL) ?? Self.defaultServerURL.absoluteString
    }
}
