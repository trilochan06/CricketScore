import AppKit
import Foundation
import Network
import OSLog

/// Owns the refresh loop. Keeps network use minimal:
/// - polls at the user's interval only while a match is live,
/// - backs off when nothing is live (up to 5 min, or until the next start time),
/// - backs off exponentially on errors,
/// - pauses while offline or asleep and refreshes as soon as either ends.
@MainActor
final class LiveMatchService {
    struct Snapshot {
        let matches: [CricketMatch]
        let scorecard: Scorecard?
        let fetchedAt: Date
    }

    enum Event {
        case willRefresh
        case updated(Snapshot)
        case failed(Error, isOffline: Bool)
    }

    var provider: CricketScoreProvider {
        didSet {
            matchesCache = []
            listFetchedAt = nil
            failures = 0
            refreshNow()
        }
    }

    var refreshInterval: TimeInterval = 15
    /// When the overlay is hidden, poll less often (the menu refreshes on open).
    var isBackgroundMode = false
    var onEvent: ((Event) -> Void)?
    /// Asked on every refresh which match needs a scorecard.
    var selectionResolver: (([CricketMatch]) -> String?)?

    private var loop: Task<Void, Never>?
    private var matchesCache: [CricketMatch] = []
    private var listFetchedAt: Date?
    private var forceListRefresh = false
    private var failures = 0
    private var isSleeping = false
    private(set) var isNetworkAvailable = true
    private let pathMonitor = NWPathMonitor()
    /// View with: log stream --predicate 'subsystem == "com.cricketscore.CricketScore"'
    private let log = Logger(subsystem: "com.cricketscore.CricketScore", category: "refresh")
    private var workspaceObservers: [NSObjectProtocol] = []

    init(provider: CricketScoreProvider) {
        self.provider = provider
        observeNetwork()
        observeSleep()
    }

    func start() {
        guard loop == nil, !isSleeping else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let delay = await self.refreshOnce()
                guard !Task.isCancelled else { return }
                try? await Task.sleep(nanoseconds: UInt64(max(delay, 1) * 1_000_000_000))
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    /// Cancels any pending wait and refreshes immediately.
    func refreshNow(reloadList: Bool = true) {
        if reloadList { forceListRefresh = true }
        stop()
        start()
    }

    // MARK: Refresh

    private func refreshOnce() async -> TimeInterval {
        let provider = self.provider
        if provider.requiresNetwork && !isNetworkAvailable {
            onEvent?(.failed(URLError(.notConnectedToInternet), isOffline: true))
            return 3600 // the path monitor restarts the loop when we're back online
        }

        onEvent?(.willRefresh)
        do {
            let listAge = listFetchedAt.map { Date().timeIntervalSince($0) } ?? .infinity
            let listInterval = max(provider.minimumListRefreshInterval, refreshInterval)
            if forceListRefresh || matchesCache.isEmpty || listAge >= listInterval || provider.minimumListRefreshInterval == 0 {
                forceListRefresh = false
                let list = try await provider.fetchLiveMatches()
                try Task.checkCancellation()
                matchesCache = list.sorted(by: Self.listOrder)
                listFetchedAt = Date()
            }

            var scorecard: Scorecard?
            let selectedID = selectionResolver?(matchesCache)
            log.notice("selected match: \(selectedID ?? "none", privacy: .public) of \(self.matchesCache.prefix(3).map { "\($0.id):\($0.status.rawValue)" }.joined(separator: ","), privacy: .public)")
            if let id = selectedID,
               let match = matchesCache.first(where: { $0.id == id }),
               match.status.hasScorecard {
                let card = try await provider.fetchScorecard(matchID: id)
                try Task.checkCancellation()
                scorecard = card
                if let index = matchesCache.firstIndex(where: { $0.id == id }) {
                    matchesCache[index] = card.match
                }
            }

            failures = 0
            let live = matchesCache.filter { $0.status.isInProgress }.count
            log.notice("\(provider.displayName, privacy: .public): \(self.matchesCache.count) matches, \(live) in progress, scorecard: \(scorecard.map { "\($0.match.shortTitle) \($0.match.currentInnings?.scoreText ?? "-")" } ?? "none", privacy: .public)")
            onEvent?(.updated(Snapshot(matches: matchesCache, scorecard: scorecard, fetchedAt: Date())))
            return nextDelay()
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                return 0
            }
            failures += 1
            let offline = Self.isOfflineError(error)
            log.error("\(provider.displayName, privacy: .public) refresh failed: \(ScoreViewModel.message(for: error), privacy: .public)")
            onEvent?(.failed(error, isOffline: offline))
            // 1×, 2×, 4×… the interval, capped at 2 minutes.
            let backoff = refreshInterval * pow(2, Double(min(failures - 1, 4)))
            return min(max(backoff, 10), 120)
        }
    }

    private func nextDelay() -> TimeInterval {
        let now = Date()
        var delay: TimeInterval
        if matchesCache.contains(where: { $0.status == .live }) {
            delay = refreshInterval
        } else if matchesCache.contains(where: { $0.status.isInProgress }) {
            delay = max(refreshInterval, 60) // breaks & rain: nothing changes quickly
        } else if let next = matchesCache.filter({ $0.status == .upcoming }).compactMap(\.startDate).min() {
            let until = next.timeIntervalSince(now)
            delay = until <= 0 ? max(refreshInterval, 60) : min(max(until, 30), 300)
        } else {
            delay = 300
        }
        if isBackgroundMode { delay = max(delay, 120) }
        return delay
    }

    static func listOrder(_ a: CricketMatch, _ b: CricketMatch) -> Bool {
        if a.status.sortRank != b.status.sortRank { return a.status.sortRank < b.status.sortRank }
        return (a.startDate ?? .distantFuture) < (b.startDate ?? .distantFuture)
    }

    static func isOfflineError(_ error: Error) -> Bool {
        guard let code = (error as? URLError)?.code else { return false }
        return [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
                .internationalRoamingOff, .cannotFindHost, .dnsLookupFailed].contains(code)
    }

    // MARK: Network & sleep

    private func observeNetwork() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied
            Task { @MainActor in self?.networkChanged(available) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "CricketScore.network", qos: .utility))
    }

    private func networkChanged(_ available: Bool) {
        let wasAvailable = isNetworkAvailable
        isNetworkAvailable = available
        guard provider.requiresNetwork else { return }
        if available && !wasAvailable {
            refreshNow()
        } else if !available && wasAvailable {
            onEvent?(.failed(URLError(.notConnectedToInternet), isOffline: true))
        }
    }

    private func observeSleep() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.isSleeping = true
                self?.stop()
            }
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.isSleeping = false
                self?.refreshNow()
            }
        })
    }
}
