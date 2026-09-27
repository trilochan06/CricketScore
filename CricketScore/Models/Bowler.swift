import Foundation

struct Bowler: Identifiable, Hashable, Sendable {
    var id: String { name }
    var name: String
    var legalBalls: Int
    var maidens: Int
    var runs: Int
    var wickets: Int

    var oversText: String { Overs.text(forBalls: legalBalls) }

    /// Runs per over; `nil` before a legal ball is bowled.
    var economy: Double? {
        legalBalls > 0 ? Double(runs) * 6 / Double(legalBalls) : nil
    }
}
