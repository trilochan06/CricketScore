import Foundation
import Observation

/// What the widget should present right now.
enum ScoreDisplay: Equatable {
    case loading
    case match(CricketMatch, Scorecard?)
    case noLiveMatches(next: CricketMatch?)
    case unavailable(message: String)
}

enum ConnectionState: Equatable {
    case ok
    case failing(message: String)
    case offline
}

struct ScoreHighlight: Equatable {
    enum Kind { case four, six, wicket }
    let kind: Kind
    let deliveryID: String
}

@MainActor
@Observable
final class ScoreViewModel {
    // Published state. Setters are guarded so views only re-render on real changes.
    private(set) var matches: [CricketMatch] = []
    private(set) var scorecard: Scorecard?
    private(set) var selectedMatchID: String?
    private(set) var lastUpdated: Date?
    private(set) var isRefreshing = false
    private(set) var connection: ConnectionState = .ok
    private(set) var hasLoaded = false
    private(set) var highlight: ScoreHighlight?
    private(set) var isUsingMockData = true
    private(set) var providerName = ""
    private(set) var mockScenario: MockScenario = .live

    var isExpanded = false
    /// "Pause Overlay" from the menu. Not persisted: relaunching shows the widget again.
    var isOverlayPaused = false
    /// Set by "Show Overlay" in the menu: keeps the widget up even when no match is live.
    private(set) var isManuallyShown = false

    @ObservationIgnored let settings: AppSettings
    @ObservationIgnored private let service: LiveMatchService
    @ObservationIgnored private var highlightTask: Task<Void, Never>?
    /// When we saw each match finish, so fresh results stay visible for a while.
    @ObservationIgnored private var completionSeenAt: [String: Date] = [:]
    @ObservationIgnored private var userPickedMatch = false

    init(settings: AppSettings) {
        self.settings = settings
        let provider = ProviderFactory.make(for: settings.dataSource, serverURL: settings.resolvedServerURL)
        self.service = LiveMatchService(provider: provider)
        applyProviderInfo(provider)

        service.refreshInterval = TimeInterval(settings.refreshInterval)
        service.selectionResolver = { [weak self] matches in self?.resolveSelection(in: matches) }
        service.onEvent = { [weak self] event in self?.handle(event) }
        if settings.rememberSelectedMatch { selectedMatchID = settings.savedMatchID }
    }

    func start() { service.start() }
    func stop() { service.stop() }

    // MARK: Derived state

    var selectedMatch: CricketMatch? {
        guard let id = selectedMatchID else { return nil }
        if let card = scorecard, card.match.id == id { return card.match }
        return matches.first { $0.id == id }
    }

    var inProgressMatches: [CricketMatch] { matches.filter { $0.status.isInProgress } }
    var upcomingMatches: [CricketMatch] { matches.filter { $0.status == .upcoming } }
    var finishedMatches: [CricketMatch] { matches.filter { $0.status == .completed || $0.status == .abandoned } }
    var hasInProgressMatch: Bool { matches.contains { $0.status.isInProgress } }

    var display: ScoreDisplay {
        if let match = selectedMatch {
            // An upcoming match more than an hour away reads better as "No live matches · Next …".
            if match.status == .upcoming, !hasInProgressMatch,
               let start = match.startDate, start.timeIntervalSinceNow > 3600 {
                return .noLiveMatches(next: match)
            }
            let card = scorecard?.match.id == match.id ? scorecard : nil
            return .match(match, card)
        }
        if hasLoaded { return .noLiveMatches(next: nil) }
        if case .failing(let message) = connection { return .unavailable(message: message) }
        if connection == .offline { return .unavailable(message: "You're offline") }
        return .loading
    }

    var shouldShowOverlay: Bool {
        guard settings.showOverlay, !isOverlayPaused else { return false }
        guard settings.hideWhenNoLiveMatches, hasLoaded, !isManuallyShown else { return true }
        if hasInProgressMatch { return true }
        if let match = selectedMatch {
            if match.status == .upcoming, let start = match.startDate, start.timeIntervalSinceNow < 3600 { return true }
            if let seen = completionSeenAt[match.id], Date().timeIntervalSince(seen) < 30 * 60 { return true }
        }
        return false
    }

    // MARK: Intents

    func select(_ matchID: String) {
        guard matchID != selectedMatchID else { return }
        userPickedMatch = true
        selectedMatchID = matchID
        if settings.rememberSelectedMatch { settings.savedMatchID = matchID }
        highlight = nil
        service.refreshNow(reloadList: false)
    }

    func refresh() { service.refreshNow() }

    func pauseOverlay() {
        isOverlayPaused = true
        isManuallyShown = false
    }

    func showOverlay() {
        isOverlayPaused = false
        isManuallyShown = true
        if !settings.showOverlay { settings.showOverlay = true }
    }

    /// Called when the menu-bar menu opens: refresh if the data is older than one interval.
    func refreshIfStale() {
        guard let last = lastUpdated else { return refresh() }
        if Date().timeIntervalSince(last) > TimeInterval(settings.refreshInterval) { refresh() }
    }

    func setRefreshInterval(_ seconds: Int) {
        service.refreshInterval = TimeInterval(seconds)
    }

    func setBackgroundMode(_ background: Bool) {
        service.isBackgroundMode = background
    }

    func setDataSource(_ source: DataSource) {
        let provider = ProviderFactory.make(for: source, serverURL: settings.resolvedServerURL)
        applyProviderInfo(provider)
        matches = []
        scorecard = nil
        hasLoaded = false
        lastUpdated = nil
        connection = .ok
        highlight = nil
        service.provider = provider
    }

    func setMockScenario(_ scenario: MockScenario) {
        mockScenario = scenario
        highlight = nil
        guard let mock = service.provider as? MockCricketScoreProvider else { return }
        Task {
            await mock.setScenario(scenario)
            self.service.refreshNow()
        }
    }

    private func applyProviderInfo(_ provider: CricketScoreProvider) {
        isUsingMockData = provider.isMock
        providerName = provider.displayName
        mockScenario = .live
    }

    // MARK: Selection

    private func resolveSelection(in list: [CricketMatch]) -> String? {
        let ids = Set(list.map(\.id))
        var chosen = selectedMatchID.flatMap { ids.contains($0) ? $0 : nil }

        // Leave a finished match once its result has been visible for a while and something else is live.
        if let id = chosen, let match = list.first(where: { $0.id == id }), match.status == .completed,
           list.contains(where: { $0.status.isInProgress }) {
            let seen = completionSeenAt[id] ?? .distantPast
            if !userPickedMatch && Date().timeIntervalSince(seen) > 5 * 60 { chosen = nil }
        }

        if chosen == nil, settings.rememberSelectedMatch, let saved = settings.savedMatchID, ids.contains(saved) {
            chosen = saved
        }
        if chosen == nil {
            chosen = list.first { $0.status == .live }?.id
                ?? list.first { $0.status.isInProgress }?.id
                ?? list.filter { $0.status == .upcoming }.min { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }?.id
                ?? list.first?.id
            userPickedMatch = false
        }
        if chosen != selectedMatchID { selectedMatchID = chosen }
        return chosen
    }

    // MARK: Events

    private func handle(_ event: LiveMatchService.Event) {
        switch event {
        case .willRefresh:
            if !isRefreshing { isRefreshing = true }
        case .updated(let snapshot):
            apply(snapshot)
            if isRefreshing { isRefreshing = false }
        case .failed(let error, let offline):
            if isRefreshing { isRefreshing = false }
            let state: ConnectionState = offline ? .offline : .failing(message: Self.message(for: error))
            if connection != state { connection = state }
        }
    }

    private func apply(_ snapshot: LiveMatchService.Snapshot) {
        let isFirstUpdate = !hasLoaded
        let hadLive = hasInProgressMatch
        let wasVisible = shouldShowOverlay
        let now = Date()

        let previous = Dictionary(matches.map { ($0.id, $0.status) }, uniquingKeysWith: { a, _ in a })
        for match in snapshot.matches where match.status == .completed {
            if previous[match.id]?.isInProgress == true { completionSeenAt[match.id] = now }
        }

        detectHighlight(old: scorecard, new: snapshot.scorecard)
        if highlight != nil, snapshot.scorecard?.match.status != .live { highlight = nil }

        if matches != snapshot.matches { matches = snapshot.matches }
        if scorecard != snapshot.scorecard { scorecard = snapshot.scorecard }
        lastUpdated = snapshot.fetchedAt
        if connection != .ok { connection = .ok }
        if !hasLoaded { hasLoaded = true }

        // "Automatically show when a match starts".
        // (The first update after launch doesn't count as "a match started".)
        if !isFirstUpdate && !hadLive && hasInProgressMatch {
            if settings.autoShowOnMatchStart {
                isOverlayPaused = false
            } else if !wasVisible {
                isOverlayPaused = true
            }
        }
    }

    private func detectHighlight(old: Scorecard?, new: Scorecard?) {
        guard let old, let new, old.match.id == new.match.id else { return }
        let known = Set(old.recentBalls.map(\.id))
        let fresh = new.recentBalls.filter { !known.contains($0.id) }
        guard !fresh.isEmpty else { return }

        let pick: (ScoreHighlight.Kind, Delivery)?
        if let w = fresh.last(where: { $0.category == .wicket }) { pick = (.wicket, w) }
        else if let s = fresh.last(where: { $0.category == .six }) { pick = (.six, s) }
        else if let f = fresh.last(where: { $0.category == .four }) { pick = (.four, f) }
        else { pick = nil }
        guard let (kind, delivery) = pick else { return }

        let event = ScoreHighlight(kind: kind, deliveryID: delivery.id)
        highlight = event
        highlightTask?.cancel()
        highlightTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled, self?.highlight == event else { return }
            self?.highlight = nil
        }
    }

    static func message(for error: Error) -> String {
        if let api = error as? CricketAPIError { return api.errorDescription ?? "Unable to update score" }
        if let url = error as? URLError {
            switch url.code {
            case .timedOut: return "The score service took too long to respond"
            case .secureConnectionFailed, .serverCertificateUntrusted: return "Couldn't connect securely"
            default: return "Unable to reach the score service"
            }
        }
        return "Unable to update score"
    }
}
