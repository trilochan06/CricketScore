import Foundation

struct Batter: Identifiable, Hashable, Sendable {
    var id: String { name }
    var name: String
    var runs: Int
    var balls: Int
    var fours: Int
    var sixes: Int
    var isStriker: Bool

    /// Runs per 100 balls; `nil` before the batter has faced a ball.
    var strikeRate: Double? {
        balls > 0 ? Double(runs) * 100 / Double(balls) : nil
    }
}
