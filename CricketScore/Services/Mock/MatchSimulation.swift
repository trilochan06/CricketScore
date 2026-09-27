import Foundation

/// Deterministic RNG so the demo matches start from the same state each launch.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// A small ball-by-ball cricket engine that drives the mock provider.
/// It advances with wall-clock time, so the UI sees a new delivery every ~10–25 s.
final class MatchSimulation {
    struct Side {
        let team: Team
        let battingOrder: [String]
        let bowlers: [String]
    }

    struct SimBatter {
        let name: String
        var runs = 0, balls = 0, fours = 0, sixes = 0
        var isOut = false
    }

    struct SimBowler {
        let name: String
        var balls = 0, maidens = 0, runs = 0, wickets = 0
    }

    struct Innings {
        let battingSide: Int
        var runs = 0, wickets = 0, legalBalls = 0
        var batters: [SimBatter] = []
        var striker = 0, nonStriker = 1
        var nextInLineup = 2
        var bowlers: [SimBowler] = []
        var currentBowler: Int?
        var lastBowler: Int?
        var bowlerBeforeLast: Int?
        var runsThisOver = 0
        var deliveries: [Delivery] = []
        var sequence = 0
        var partnership = Partnership(runs: 0, balls: 0)
        var lastWicket: String?
    }

    enum Phase {
        case scheduled
        case live
        case inningsBreak(until: Date)
        case completed(result: String, at: Date)
    }

    let id: String
    let format: MatchFormat
    let title: String
    let series: String
    let venue: String
    let sides: [Side]
    let battingFirst: Int
    let toss: String
    let startDate: Date

    private(set) var innings: [Innings] = []
    private(set) var phase: Phase = .scheduled
    /// Outcomes bowled before random ones — used to show a 4, W and 6 early in the demo.
    var scriptedOutcomes: [Delivery.Outcome] = []
    var ballInterval: ClosedRange<Double> = 10...24
    var inningsBreakDuration: TimeInterval = 90

    private var rng: SeededGenerator
    private var nextBallAt: Date

    private var oversLimit: Int { format.oversPerInnings ?? 90 }
    private var maxBallsPerBowler: Int { (format.oversPerInnings ?? 450) / 5 * 6 }

    init(id: String, format: MatchFormat, title: String, series: String, venue: String,
         sides: [Side], battingFirst: Int, toss: String, startDate: Date, seed: UInt64) {
        self.id = id
        self.format = format
        self.title = title
        self.series = series
        self.venue = venue
        self.sides = sides
        self.battingFirst = battingFirst
        self.toss = toss
        self.startDate = startDate
        self.rng = SeededGenerator(seed: seed)
        self.nextBallAt = startDate
    }

    var isCompleted: Bool {
        if case .completed = phase { return true }
        return false
    }

    var completedAt: Date? {
        if case .completed(_, let at) = phase { return at }
        return nil
    }

    // MARK: Setup helpers

    /// Starts the match and bowls `balls` deliveries instantly (for demo state).
    func fastForward(balls: Int, now: Date = Date()) {
        if innings.isEmpty { startInnings(now: now) }
        phase = .live
        for _ in 0..<balls {
            guard case .live = phase else { break }
            bowlBall(now: now)
        }
        nextBallAt = now.addingTimeInterval(randomGap())
    }

    /// Installs a hand-written state (used for the IND vs AUS demo chase).
    func install(innings: [Innings], now: Date = Date()) {
        self.innings = innings
        phase = .live
        nextBallAt = now.addingTimeInterval(4)
    }

    // MARK: Time

    func advance(to now: Date) {
        var steps = 0
        while steps < 60 {
            steps += 1
            switch phase {
            case .scheduled:
                guard now >= startDate else { return }
                startInnings(now: now)
                phase = .live
                nextBallAt = max(startDate, now.addingTimeInterval(-1)).addingTimeInterval(randomGap())
            case .live:
                guard nextBallAt <= now else { return }
                bowlBall(now: nextBallAt)
                nextBallAt = nextBallAt.addingTimeInterval(randomGap())
            case .inningsBreak(let until):
                guard now >= until else { return }
                startInnings(now: until)
                phase = .live
                nextBallAt = until.addingTimeInterval(randomGap())
            case .completed:
                return
            }
        }
        // Long sleep or pause: don't replay hours of cricket, just resume from now.
        if nextBallAt < now { nextBallAt = now.addingTimeInterval(randomGap()) }
    }

    private func randomGap() -> TimeInterval {
        Double.random(in: ballInterval, using: &rng)
    }

    // MARK: Engine

    private func startInnings(now: Date) {
        let side = innings.isEmpty ? battingFirst : 1 - battingFirst
        let order = sides[side].battingOrder
        var inn = Innings(battingSide: side)
        inn.batters = order.prefix(2).map { SimBatter(name: $0) }
        inn.bowlers = sides[1 - side].bowlers.map { SimBowler(name: $0) }
        innings.append(inn)
    }

    private func nextOutcome() -> Delivery.Outcome {
        if !scriptedOutcomes.isEmpty { return scriptedOutcomes.removeFirst() }
        let table: [(Delivery.Outcome, Double)]
        switch format {
        case .t20, .t10:
            table = [(.dot, 31), (.runs(1), 34), (.runs(2), 9), (.runs(3), 1), (.four, 12), (.six, 6),
                     (.wicket, 4), (.wide(1), 3), (.noBall(1), 1), (.legBye(1), 2)]
        default:
            table = [(.dot, 44), (.runs(1), 33), (.runs(2), 7), (.runs(3), 1), (.four, 8), (.six, 2),
                     (.wicket, 2.6), (.wide(1), 2), (.noBall(1), 0.5), (.legBye(1), 1.5)]
        }
        let total = table.reduce(0) { $0 + $1.1 }
        var pick = Double.random(in: 0..<total, using: &rng)
        for (outcome, weight) in table {
            if pick < weight { return outcome }
            pick -= weight
        }
        return .dot
    }

    private func pickBowler(_ inn: Innings) -> Int {
        let eligible = inn.bowlers.indices.filter {
            $0 != inn.lastBowler && inn.bowlers[$0].balls < maxBallsPerBowler
        }
        if let pair = inn.bowlerBeforeLast, eligible.contains(pair) { return pair }
        if let fresh = eligible.min(by: { inn.bowlers[$0].balls < inn.bowlers[$1].balls }) { return fresh }
        return inn.bowlers.indices.first { $0 != inn.lastBowler } ?? 0
    }

    private func bowlBall(now: Date) {
        guard var inn = innings.last else { return }
        let lineup = sides[inn.battingSide].battingOrder
        let bowler = inn.currentBowler ?? pickBowler(inn)
        inn.currentBowler = bowler
        let over = inn.legalBalls / 6
        let outcome = nextOutcome()
        var runs = 0

        switch outcome {
        case .wide(let n), .noBall(let n):
            runs = n
            inn.bowlers[bowler].runs += n
            inn.runsThisOver += n
        case .bye(let n), .legBye(let n):
            runs = n
            inn.batters[inn.striker].balls += 1
            inn.bowlers[bowler].balls += 1
        case .dot, .runs, .four, .six:
            runs = switch outcome {
            case .runs(let n): n
            case .four: 4
            case .six: 6
            default: 0
            }
            inn.batters[inn.striker].runs += runs
            inn.batters[inn.striker].balls += 1
            if case .four = outcome { inn.batters[inn.striker].fours += 1 }
            if case .six = outcome { inn.batters[inn.striker].sixes += 1 }
            inn.bowlers[bowler].balls += 1
            inn.bowlers[bowler].runs += runs
            inn.runsThisOver += runs
        case .wicket:
            inn.batters[inn.striker].balls += 1
            inn.batters[inn.striker].isOut = true
            inn.bowlers[bowler].balls += 1
            inn.bowlers[bowler].wickets += 1
            inn.wickets += 1
        }

        let isLegal: Bool = {
            if case .wide = outcome { return false }
            if case .noBall = outcome { return false }
            return true
        }()
        inn.runs += runs
        if isLegal { inn.legalBalls += 1 }
        inn.partnership.runs += runs
        if isLegal { inn.partnership.balls += 1 }

        inn.sequence += 1
        inn.deliveries.append(Delivery(id: "\(id)-\(innings.count)-\(inn.sequence)", outcome: outcome, over: over))
        if inn.deliveries.count > 24 { inn.deliveries.removeFirst(inn.deliveries.count - 24) }

        // Strike rotation on odd runs.
        switch outcome {
        case .runs(let n), .bye(let n), .legBye(let n):
            if n % 2 == 1 { swap(&inn.striker, &inn.nonStriker) }
        default: break
        }

        if case .wicket = outcome {
            let out = inn.batters[inn.striker]
            inn.lastWicket = "\(out.name) \(out.runs) (\(out.balls))"
            inn.partnership = Partnership(runs: 0, balls: 0)
            if inn.wickets < 10, inn.nextInLineup < lineup.count {
                inn.batters.append(SimBatter(name: lineup[inn.nextInLineup]))
                inn.nextInLineup += 1
                inn.striker = inn.batters.count - 1
            }
        }

        // End of over: maiden check, change ends, new bowler.
        if isLegal && inn.legalBalls % 6 == 0 {
            if inn.runsThisOver == 0 { inn.bowlers[bowler].maidens += 1 }
            swap(&inn.striker, &inn.nonStriker)
            inn.bowlerBeforeLast = inn.lastBowler
            inn.lastBowler = bowler
            inn.currentBowler = nil
            inn.runsThisOver = 0
        }

        innings[innings.count - 1] = inn

        // Match / innings transitions.
        let battingTeam = sides[inn.battingSide].team
        if innings.count == 2 {
            let target = innings[0].runs + 1
            if inn.runs >= target {
                let left = 10 - inn.wickets
                phase = .completed(result: "\(battingTeam.name) won by \(left) wicket\(left == 1 ? "" : "s")", at: now)
                return
            }
        }
        let allOut = inn.wickets >= 10
        let oversDone = inn.legalBalls >= oversLimit * 6
        guard allOut || oversDone else { return }

        if innings.count == 1 {
            phase = .inningsBreak(until: now.addingTimeInterval(inningsBreakDuration))
        } else {
            let target = innings[0].runs + 1
            let margin = target - 1 - inn.runs
            let firstTeam = sides[innings[0].battingSide].team
            let result = margin == 0 ? "Match tied" : "\(firstTeam.name) won by \(margin) run\(margin == 1 ? "" : "s")"
            phase = .completed(result: result, at: now)
        }
    }

    // MARK: Snapshots

    private var target: Int? { innings.count == 2 ? innings[0].runs + 1 : nil }

    func matchSnapshot(now: Date) -> CricketMatch {
        let scores = innings.map {
            InningsScore(team: sides[$0.battingSide].team, runs: $0.runs, wickets: $0.wickets, legalBalls: $0.legalBalls)
        }
        let status: MatchStatus
        var statusText: String
        var result: String?

        switch phase {
        case .scheduled:
            status = .upcoming
            statusText = "Starts \(startDate.formatted(date: .omitted, time: .shortened))"
        case .live:
            status = .live
            if let target, let inn = innings.last {
                let need = target - inn.runs
                let left = oversLimit * 6 - inn.legalBalls
                statusText = "\(sides[inn.battingSide].team.shortName) need \(need) run\(need == 1 ? "" : "s") from \(left) ball\(left == 1 ? "" : "s")"
            } else {
                statusText = toss
            }
        case .inningsBreak:
            status = .inningsBreak
            let chasing = sides[1 - battingFirst].team
            statusText = "Innings break · \(chasing.shortName) need \((innings.first?.runs ?? 0) + 1) to win"
        case .completed(let text, _):
            status = .completed
            statusText = text
            result = text
        }

        return CricketMatch(
            id: id,
            teams: sides.map(\.team),
            format: format,
            title: title,
            series: series,
            venue: venue,
            status: status,
            statusText: statusText,
            startDate: startDate,
            innings: scores,
            target: target ?? (status == .inningsBreak ? (innings.first?.runs ?? 0) + 1 : nil),
            result: result,
            toss: toss
        )
    }

    func scorecardSnapshot(now: Date) -> Scorecard {
        let match = matchSnapshot(now: now)
        guard let inn = innings.last else {
            return Scorecard(match: match, batters: [], bowler: nil, recentBalls: [], partnership: nil, lastWicket: nil,
                             currentRunRate: nil, requiredRunRate: nil, target: nil, runsRequired: nil, ballsRemaining: nil)
        }

        let atCrease: Bool = if case .live = phase { true } else { false }
        var batters: [Batter] = []
        if atCrease {
            for index in [inn.striker, inn.nonStriker] where inn.batters.indices.contains(index) {
                let b = inn.batters[index]
                guard !b.isOut else { continue }
                batters.append(Batter(name: b.name, runs: b.runs, balls: b.balls, fours: b.fours, sixes: b.sixes,
                                      isStriker: index == inn.striker))
            }
        }

        let bowlerIndex = inn.currentBowler ?? inn.lastBowler
        let bowler = atCrease ? bowlerIndex.map { i -> Bowler in
            let b = inn.bowlers[i]
            return Bowler(name: b.name, legalBalls: b.balls, maidens: b.maidens, runs: b.runs, wickets: b.wickets)
        } : nil

        let crr = inn.legalBalls > 0 ? Double(inn.runs) * 6 / Double(inn.legalBalls) : nil
        var rrr: Double?
        var runsRequired: Int?
        var ballsRemaining: Int?
        if let target, !isCompleted {
            let need = max(0, target - inn.runs)
            let left = max(0, oversLimit * 6 - inn.legalBalls)
            runsRequired = need
            ballsRemaining = left
            rrr = left > 0 ? Double(need) * 6 / Double(left) : nil
        }

        return Scorecard(
            match: match,
            batters: batters,
            bowler: bowler,
            recentBalls: Array(inn.deliveries.suffix(12)),
            partnership: atCrease ? inn.partnership : nil,
            lastWicket: inn.lastWicket,
            currentRunRate: crr,
            requiredRunRate: rrr,
            target: match.target,
            runsRequired: runsRequired,
            ballsRemaining: ballsRemaining
        )
    }
}
