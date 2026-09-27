import Foundation

/// A source of cricket data. Swap implementations to change where scores come from.
///
///     CricketScoreProvider (this protocol)
///         ↓   MockCricketScoreProvider  — simulated live matches, no network, no key
///         ↓   LiveCricketScoreProvider  — CricketData.org REST API
///     LiveMatchService   — scheduling, backoff, offline/sleep handling
///         ↓
///     ScoreViewModel     — selection, highlights, display state
///         ↓
///     SwiftUI views
protocol CricketScoreProvider: Sendable {
    /// Shown in Settings and the footer.
    var displayName: String { get }
    /// True for simulated data, so the UI can label it.
    var isMock: Bool { get }
    /// Mock providers work offline; real ones should pause while the network is down.
    var requiresNetwork: Bool { get }
    /// Minimum seconds between `fetchLiveMatches` calls. Rate-limited APIs set this
    /// high so each poll only fetches the selected match's scorecard.
    var minimumListRefreshInterval: TimeInterval { get }

    /// Live, upcoming, and recently finished matches.
    func fetchLiveMatches() async throws -> [CricketMatch]
    /// Detailed scorecard for one match (includes an up-to-date match summary).
    func fetchScorecard(matchID: String) async throws -> Scorecard
}

extension CricketScoreProvider {
    var isMock: Bool { false }
    var requiresNetwork: Bool { true }
    var minimumListRefreshInterval: TimeInterval { 0 }
}

enum CricketAPIError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidResponse
    case http(status: Int)
    case rateLimited
    case provider(message: String)
    case decoding
    case matchNotFound

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: "Add an API key in Settings → Data"
        case .invalidResponse: "The score service sent an unexpected response"
        case .http(let status): "The score service returned an error (\(status))"
        case .rateLimited: "API request limit reached — try a slower refresh rate"
        case .provider(let message): message
        case .decoding: "Couldn't read the score data"
        case .matchNotFound: "This match is no longer available"
        }
    }
}
