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
        static let favoriteTeams = "favoriteTeams"
        static let includeTeamVariants = "includeTeamVariants"
        static let onlyFavorites = "onlyFavorites"
        static let alertsEnabled = "alertsEnabled"
        static let alertWickets = "alertWickets"
        static let alertMilestones = "alertMilestones"
        static let alertMatchEvents = "alertMatchEvents"
        static let alertsWhilePaused = "alertsWhilePaused"
        static let hideInFullScreen = "hideInFullScreen"
        static let hideDuringCalls = "hideDuringCalls"
        static let hideFromScreenSharing = "hideFromScreenSharing"
    }

    /// Suggestions for the favorite-team picker (any team name can also be typed in).
    static let suggestedTeams = ["India", "Australia", "England", "South Africa", "New Zealand", "Pakistan",
                                 "Sri Lanka", "Bangladesh", "West Indies", "Afghanistan", "Ireland", "Zimbabwe",
                                 "Netherlands", "Scotland", "Nepal", "United Arab Emirates", "United States of America"]

    /// Where the Cricket Live server runs:
    ///   1. `CRICKET_SERVER_URL` environment variable (development),
    ///   2. `CricketServerURL` in Info.plist (baked in by Scripts/release.sh for public builds),
    ///   3. a local server on port 8787.
    nonisolated static let defaultServerURL: URL = {
        if let env = ProcessInfo.processInfo.environment["CRICKET_SERVER_URL"], let url = URL(string: env) { return url }
        if let plist = Bundle.main.object(forInfoDictionaryKey: "CricketServerURL") as? String,
           !plist.isEmpty, !plist.hasPrefix("$("), let url = URL(string: plist) { return url }
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

    // Favorite teams
    var favoriteTeams: [String] { didSet { defaults.set(favoriteTeams, forKey: Key.favoriteTeams) } }
    /// "India" also follows India Women, India A and India Under-19s.
    var includeTeamVariants: Bool { didSet { defaults.set(includeTeamVariants, forKey: Key.includeTeamVariants) } }
    /// Only show the widget for favorite teams' matches.
    var onlyFavorites: Bool { didSet { defaults.set(onlyFavorites, forKey: Key.onlyFavorites) } }

    // Notch alerts
    var alertsEnabled: Bool { didSet { defaults.set(alertsEnabled, forKey: Key.alertsEnabled) } }
    var alertWickets: Bool { didSet { defaults.set(alertWickets, forKey: Key.alertWickets) } }
    var alertMilestones: Bool { didSet { defaults.set(alertMilestones, forKey: Key.alertMilestones) } }
    var alertMatchEvents: Bool { didSet { defaults.set(alertMatchEvents, forKey: Key.alertMatchEvents) } }
    /// Briefly show alerts even when the widget is paused or hidden between matches.
    var alertsWhilePaused: Bool { didSet { defaults.set(alertsWhilePaused, forKey: Key.alertsWhilePaused) } }

    // Focus
    var hideInFullScreen: Bool { didSet { defaults.set(hideInFullScreen, forKey: Key.hideInFullScreen) } }
    var hideDuringCalls: Bool { didSet { defaults.set(hideDuringCalls, forKey: Key.hideDuringCalls) } }
    var hideFromScreenSharing: Bool { didSet { defaults.set(hideFromScreenSharing, forKey: Key.hideFromScreenSharing) } }

    func isFavorite(_ team: Team) -> Bool {
        favoriteTeams.contains { fav in
            let f = fav.trimmingCharacters(in: .whitespaces)
            guard !f.isEmpty else { return false }
            if team.name.caseInsensitiveCompare(f) == .orderedSame || team.shortName.caseInsensitiveCompare(f) == .orderedSame { return true }
            return includeTeamVariants && team.name.lowercased().hasPrefix(f.lowercased() + " ")
        }
    }

    func isFavorite(_ match: CricketMatch) -> Bool {
        match.teams.contains(where: isFavorite)
    }

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
            Key.refreshInterval: 15, // ball-by-ball: ~8 s average delay; only while a match is live
            Key.autoShowOnMatchStart: true,
            Key.hideWhenNoLiveMatches: true,
            Key.rememberSelectedMatch: true,
            Key.dataSource: DataSource.espn.rawValue,
            Key.serverURL: Self.defaultServerURL.absoluteString,
            Key.favoriteTeams: [String](),
            Key.includeTeamVariants: true,
            Key.onlyFavorites: false,
            Key.alertsEnabled: true,
            Key.alertWickets: true,
            Key.alertMilestones: true,
            Key.alertMatchEvents: true,
            Key.alertsWhilePaused: true,
            Key.hideInFullScreen: true,
            Key.hideDuringCalls: true,
            Key.hideFromScreenSharing: true,
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
        refreshInterval = Self.refreshOptions.contains(interval) ? interval : 15
        autoShowOnMatchStart = defaults.bool(forKey: Key.autoShowOnMatchStart)
        hideWhenNoLiveMatches = defaults.bool(forKey: Key.hideWhenNoLiveMatches)
        rememberSelectedMatch = defaults.bool(forKey: Key.rememberSelectedMatch)
        savedMatchID = defaults.string(forKey: Key.savedMatchID)
        dataSource = DataSource(rawValue: defaults.string(forKey: Key.dataSource) ?? "") ?? .espn
        serverURL = defaults.string(forKey: Key.serverURL) ?? Self.defaultServerURL.absoluteString
        favoriteTeams = defaults.stringArray(forKey: Key.favoriteTeams) ?? []
        includeTeamVariants = defaults.bool(forKey: Key.includeTeamVariants)
        onlyFavorites = defaults.bool(forKey: Key.onlyFavorites)
        alertsEnabled = defaults.bool(forKey: Key.alertsEnabled)
        alertWickets = defaults.bool(forKey: Key.alertWickets)
        alertMilestones = defaults.bool(forKey: Key.alertMilestones)
        alertMatchEvents = defaults.bool(forKey: Key.alertMatchEvents)
        alertsWhilePaused = defaults.bool(forKey: Key.alertsWhilePaused)
        hideInFullScreen = defaults.bool(forKey: Key.hideInFullScreen)
        hideDuringCalls = defaults.bool(forKey: Key.hideDuringCalls)
        hideFromScreenSharing = defaults.bool(forKey: Key.hideFromScreenSharing)
    }
}
