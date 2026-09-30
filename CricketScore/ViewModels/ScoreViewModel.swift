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

/// A short notch banner for a key moment (wicket elsewhere, milestone, last over, start, result).
struct MatchAlert: Equatable, Identifiable {
    enum Kind: Equatable { case wicket, milestone, lastOver, started, result }
    let id = UUID()
    let kind: Kind
    let title: String
    let detail: String
    let matchID: String
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
    private(set) var alert: MatchAlert?
    /// Set by FocusMonitor: a full-screen app or video call is in front, so stay out of the way.
    private(set) var focusSuppressed = false

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
    @ObservationIgnored private var alertQueue: [MatchAlert] = []
    @ObservationIgnored private var alertTask: Task<Void, Never>?

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

    /// Matches the widget cares about: everything, or only favorite teams' matches.
    var relevantMatches: [CricketMatch] {
        settings.onlyFavorites && !settings.favoriteTeams.isEmpty ? matches.filter(settings.isFavorite) : matches
    }

    var inProgressMatches: [CricketMatch] { matches.filter { $0.status.isInProgress } }
    var upcomingMatches: [CricketMatch] { matches.filter { $0.status == .upcoming } }
    var finishedMatches: [CricketMatch] { matches.filter { $0.status == .completed || $0.status == .abandoned } }
    var hasInProgressMatch: Bool { relevantMatches.contains { $0.status.isInProgress } }

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
        guard settings.showOverlay, !focusSuppressed else { return false }
        // A notch alert pops up briefly even while paused / hidden between matches.
        if alert != nil, settings.alertsWhilePaused { return true }
        guard !isOverlayPaused else { return false }
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

    func setFocusSuppressed(_ suppressed: Bool) {
        guard focusSuppressed != suppressed else { return }
        focusSuppressed = suppressed
        if suppressed { isExpanded = false }
    }

    func dismissAlert() {
        alertTask?.cancel()
        alert = nil
        showNextAlert()
    }

    /// Re-evaluate selection after favorites change.
    func favoritesChanged() {
        userPickedMatch = false
        service.refreshNow(reloadList: false)
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

        // A favorite team's match that's in progress beats an automatically chosen other match.
        let favorites = settings.favoriteTeams.isEmpty ? [] : list.filter(settings.isFavorite)
        if !userPickedMatch, let id = chosen, !favorites.contains(where: { $0.id == id }),
           let fav = favorites.first(where: { $0.status == .live }) ?? favorites.first(where: { $0.status.isInProgress }) {
            chosen = fav.id
        }

        if chosen == nil, settings.rememberSelectedMatch, let saved = settings.savedMatchID, ids.contains(saved) {
            chosen = saved
        }
        if chosen == nil {
            let pool = settings.onlyFavorites && !favorites.isEmpty ? favorites : list
            chosen = Self.bestMatch(in: favorites) ?? Self.bestMatch(in: pool) ?? pool.first?.id
            userPickedMatch = false
        }
        if chosen != selectedMatchID { selectedMatchID = chosen }
        return chosen
    }

    /// Live first, then breaks/rain, then the soonest upcoming match.
    private static func bestMatch(in list: [CricketMatch]) -> String? {
        if let live = list.first(where: { $0.status == .live }) { return live.id }
        if let inProgress = list.first(where: { $0.status.isInProgress }) { return inProgress.id }
        let upcoming = list.filter { $0.status == .upcoming }
        let soonest = upcoming.min { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
        return soonest?.id
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

        if !isFirstUpdate {
            detectAlerts(oldMatches: matches, newMatches: snapshot.matches, oldCard: scorecard, newCard: snapshot.scorecard)
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

    // MARK: Alerts

    func detectAlerts(oldMatches: [CricketMatch], newMatches: [CricketMatch], oldCard: Scorecard?, newCard: Scorecard?) {
        guard settings.alertsEnabled else { return }
        let old = Dictionary(oldMatches.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        for match in newMatches {
            guard let before = old[match.id] else { continue }
            let followed = settings.isFavorite(match) || match.id == selectedMatchID
            guard followed else { continue }

            if settings.alertMatchEvents {
                if before.status == .upcoming && match.status.isInProgress {
                    enqueueAlert(.init(kind: .started, title: "Match started", detail: match.shortTitle, matchID: match.id))
                }
                if before.status.isInProgress && (match.status == .completed || match.status == .abandoned) {
                    let result = match.result ?? match.statusText
                    enqueueAlert(.init(kind: .result, title: "Result", detail: Format.shortResult(result, match: match), matchID: match.id))
                }
            }
            // Wickets in other followed matches (the selected match already flashes W on its own).
            if settings.alertWickets, match.id != selectedMatchID,
               let a = before.currentInnings, let b = match.currentInnings, a.team == b.team, b.wickets > a.wickets {
                enqueueAlert(.init(kind: .wicket, title: "Wicket",
                                   detail: "\(b.team.shortName) \(b.scoreText) v \(match.otherTeam?.shortName ?? "")", matchID: match.id))
            }
        }

        // Milestones and the last over for the selected match.
        guard let oldCard, let newCard, oldCard.match.id == newCard.match.id, newCard.match.status == .live else { return }
        if settings.alertMilestones {
            for batter in newCard.batters {
                guard let prev = oldCard.batters.first(where: { $0.name == batter.name }) else { continue }
                for mark in [50, 100, 150, 200] where prev.runs < mark && batter.runs >= mark {
                    let surname = batter.name.split(separator: " ").last.map(String.init) ?? batter.name
                    enqueueAlert(.init(kind: .milestone, title: "\(mark) for \(surname)",
                                       detail: "\(batter.runs) off \(batter.balls) balls", matchID: newCard.match.id))
                }
            }
        }
        if settings.alertMatchEvents, let was = oldCard.ballsRemaining, let now = newCard.ballsRemaining,
           was > 6, now <= 6, now > 0, let need = newCard.runsRequired, need > 0 {
            let team = newCard.match.battingTeam?.shortName ?? ""
            enqueueAlert(.init(kind: .lastOver, title: "Last over", detail: "\(team) need \(need) from \(now)", matchID: newCard.match.id))
        }
    }

    func enqueueAlert(_ alert: MatchAlert) {
        guard !focusSuppressed else { return }
        alertQueue.append(alert)
        if alertQueue.count > 4 { alertQueue.removeFirst(alertQueue.count - 4) }
        if self.alert == nil { showNextAlert() }
    }

    private func showNextAlert() {
        guard alert == nil, !alertQueue.isEmpty else { return }
        let next = alertQueue.removeFirst()
        alert = next
        alertTask?.cancel()
        alertTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled, let self, self.alert?.id == next.id else { return }
            self.alert = nil
            try? await Task.sleep(nanoseconds: 400_000_000)
            self.showNextAlert()
        }
    }

    #if DEBUG
    /// Development aids for snapshots / tests.
    func debugShowAlert(_ alert: MatchAlert) { enqueueAlert(alert) }
    var debugPendingAlerts: [MatchAlert] { (alert.map { [$0] } ?? []) + alertQueue }
    func debugSelect(_ id: String) { selectedMatchID = id }
    #endif

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
