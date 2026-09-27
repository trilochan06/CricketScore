import Foundation

struct Partnership: Hashable, Sendable {
    var runs: Int
    var balls: Int
}

/// Detailed state of a single match. `match` carries the freshest summary so a
/// scorecard fetch alone is enough to refresh the selected match.
struct Scorecard: Hashable, Sendable {
    var match: CricketMatch
    /// Batters currently at the crease (0–2).
    var batters: [Batter]
    var bowler: Bowler?
    /// Most recent deliveries, oldest first. Empty when the provider has no ball-by-ball feed.
    var recentBalls: [Delivery]
    var partnership: Partnership?
    var lastWicket: String?
    var currentRunRate: Double?
    var requiredRunRate: Double?
    var target: Int?
    var runsRequired: Int?
    var ballsRemaining: Int?
}
