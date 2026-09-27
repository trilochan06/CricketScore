import Foundation

enum MatchFormat: String, Sendable, CaseIterable {
    case test, odi, t20, t10, other

    var displayName: String {
        switch self {
        case .test: "Test"
        case .odi: "ODI"
        case .t20: "T20"
        case .t10: "T10"
        case .other: "Match"
        }
    }

    /// Overs per innings for limited-overs formats; `nil` for Tests.
    var oversPerInnings: Int? {
        switch self {
        case .odi: 50
        case .t20: 20
        case .t10: 10
        case .test, .other: nil
        }
    }
}

enum MatchStatus: String, Sendable {
    case upcoming, live, inningsBreak, rainDelay, completed, abandoned

    /// The match has started and hasn't finished.
    var isInProgress: Bool {
        self == .live || self == .inningsBreak || self == .rainDelay
    }

    /// Whether it is worth fetching a detailed scorecard for this match.
    var hasScorecard: Bool {
        self != .upcoming && self != .abandoned
    }

    /// Ordering used for match lists: live first, then breaks, upcoming, results.
    var sortRank: Int {
        switch self {
        case .live: 0
        case .rainDelay, .inningsBreak: 1
        case .upcoming: 2
        case .completed: 3
        case .abandoned: 4
        }
    }
}

struct InningsScore: Hashable, Sendable {
    var team: Team
    var runs: Int
    var wickets: Int
    var legalBalls: Int

    var scoreText: String { wickets >= 10 ? "\(runs)" : "\(runs)/\(wickets)" }
    var oversText: String { Overs.text(forBalls: legalBalls) }
}

enum Overs {
    /// 194 balls → "32.2", 300 balls → "50".
    static func text(forBalls balls: Int) -> String {
        let b = max(0, balls)
        return b % 6 == 0 ? "\(b / 6)" : "\(b / 6).\(b % 6)"
    }

    /// Cricket notation 32.2 (32 overs, 2 balls) → 194 balls.
    static func balls(fromOvers overs: Double) -> Int {
        guard overs.isFinite, overs > 0 else { return 0 }
        let whole = Int(overs)
        let part = Int(((overs - Double(whole)) * 10).rounded())
        return whole * 6 + min(max(part, 0), 5)
    }
}

struct CricketMatch: Identifiable, Hashable, Sendable {
    let id: String
    var teams: [Team]
    var format: MatchFormat
    /// e.g. "3rd ODI".
    var title: String
    /// e.g. "Australia tour of India". May be empty.
    var series: String
    var venue: String
    var status: MatchStatus
    /// Human-readable status from the provider, e.g. "India need 58 runs from 106 balls".
    var statusText: String
    var startDate: Date?
    /// Innings in the order they were batted.
    var innings: [InningsScore]
    /// Runs needed to win for the side batting last, when known.
    var target: Int?
    var result: String?
    var toss: String?

    var teamA: Team { teams.first ?? .unknown }
    var teamB: Team { teams.count > 1 ? teams[1] : .unknown }

    var currentInnings: InningsScore? { innings.last }

    var battingTeam: Team? { status == .live || status == .rainDelay ? innings.last?.team : nil }

    func latestInnings(for team: Team) -> InningsScore? {
        innings.last { $0.team == team }
    }

    /// Teams ordered by who batted first (falls back to listed order).
    var teamsInBattingOrder: [Team] {
        guard let first = innings.first?.team else { return [teamA, teamB] }
        return [first, first == teamA ? teamB : teamA]
    }

    /// The opposition of the batting side (for compact displays).
    var otherTeam: Team? {
        guard let batting = innings.last?.team else { return nil }
        return batting == teamA ? teamB : teamA
    }

    var shortTitle: String { "\(teamA.shortName) vs \(teamB.shortName)" }
    var fullTitle: String { "\(teamA.name) vs \(teamB.name)" }

    /// "3rd ODI · Australia tour of India" without empty parts.
    var subtitle: String {
        [title, series].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
