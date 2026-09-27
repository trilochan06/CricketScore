import Foundation

/// States you can force from Settings → Data to test every part of the UI.
enum MockScenario: String, CaseIterable, Identifiable, Sendable {
    case live, inningsBreak, rainDelay, upcoming, completed, noLiveMatches, nothingScheduled, apiError, offline

    var id: String { rawValue }

    var title: String {
        switch self {
        case .live: "Live matches (simulated)"
        case .inningsBreak: "Innings break"
        case .rainDelay: "Rain delay"
        case .upcoming: "Match starting soon"
        case .completed: "Match ended"
        case .noLiveMatches: "No live matches, next later"
        case .nothingScheduled: "Nothing scheduled"
        case .apiError: "API error"
        case .offline: "Offline"
        }
    }
}

/// Simulated data source. Works with no network and no API key.
///
/// ─────────────────────────────────────────────────────────────────────────────
/// To use real data, pick "CricketData.org" in Settings → Data, or change
/// `ProviderFactory.make(for:)` in LiveCricketScoreProvider.swift.
/// ─────────────────────────────────────────────────────────────────────────────
actor MockCricketScoreProvider: CricketScoreProvider {
    nonisolated var displayName: String { "Demo data" }
    nonisolated var isMock: Bool { true }
    nonisolated var requiresNetwork: Bool { false }

    private var scenario: MockScenario = .live
    private var scenarioStartedAt = Date()
    private var simulations: [MatchSimulation] = []
    private let factories: [() -> MatchSimulation]

    init() {
        factories = [MockData.indiaAustralia, MockData.englandSouthAfrica, MockData.pakistanNewZealand]
        simulations = factories.map { $0() }
    }

    func setScenario(_ scenario: MockScenario) {
        self.scenario = scenario
        scenarioStartedAt = Date()
    }

    func fetchLiveMatches() async throws -> [CricketMatch] {
        try await simulateLatency()
        let now = Date()
        switch scenario {
        case .live:
            tick(now)
            return simulations.map { $0.matchSnapshot(now: now) } + [MockData.sriLankaBangladeshResult(now: now)]
        case .inningsBreak:
            return [MockData.inningsBreak(from: simulations[0], now: now).match]
        case .rainDelay:
            return [MockData.rainDelay(from: simulations[0], now: now).match]
        case .upcoming:
            return [MockData.upcoming(startingAt: scenarioStartedAt.addingTimeInterval(42 * 60))]
        case .completed:
            return [MockData.completed(now: now).match]
        case .noLiveMatches:
            return [MockData.upcoming(startingAt: MockData.nextEvening(after: now))]
        case .nothingScheduled:
            return []
        case .apiError:
            throw CricketAPIError.http(status: 503)
        case .offline:
            throw URLError(.notConnectedToInternet)
        }
    }

    func fetchScorecard(matchID: String) async throws -> Scorecard {
        try await simulateLatency()
        let now = Date()
        switch scenario {
        case .live:
            tick(now)
            if let sim = simulations.first(where: { $0.id == matchID }) { return sim.scorecardSnapshot(now: now) }
            let result = MockData.sriLankaBangladeshResult(now: now)
            if result.id == matchID { return MockData.emptyScorecard(for: result) }
            throw CricketAPIError.matchNotFound
        case .inningsBreak:
            return MockData.inningsBreak(from: simulations[0], now: now)
        case .rainDelay:
            return MockData.rainDelay(from: simulations[0], now: now)
        case .completed:
            return MockData.completed(now: now)
        case .upcoming, .noLiveMatches, .nothingScheduled:
            throw CricketAPIError.matchNotFound
        case .apiError:
            throw CricketAPIError.http(status: 503)
        case .offline:
            throw URLError(.notConnectedToInternet)
        }
    }

    private func tick(_ now: Date) {
        for i in simulations.indices {
            simulations[i].advance(to: now)
            // Restart finished demo matches after a few minutes so the demo never runs dry.
            if let ended = simulations[i].completedAt, now.timeIntervalSince(ended) > 180 {
                simulations[i] = factories[i]()
            }
        }
    }

    private func simulateLatency() async throws {
        try await Task.sleep(nanoseconds: UInt64.random(in: 120_000_000...320_000_000))
    }
}

// MARK: - Demo fixtures

enum MockData {
    static let india = Team(name: "India", shortName: "IND")
    static let australia = Team(name: "Australia", shortName: "AUS")
    static let england = Team(name: "England", shortName: "ENG")
    static let southAfrica = Team(name: "South Africa", shortName: "SA")
    static let pakistan = Team(name: "Pakistan", shortName: "PAK")
    static let newZealand = Team(name: "New Zealand", shortName: "NZ")
    static let sriLanka = Team(name: "Sri Lanka", shortName: "SL")
    static let bangladesh = Team(name: "Bangladesh", shortName: "BAN")

    /// India chasing 242 in the 3rd ODI, at 184/4 after 32.2 overs.
    static func indiaAustralia() -> MatchSimulation {
        let sides = [
            MatchSimulation.Side(
                team: india,
                battingOrder: ["Rohit Sharma", "Yashasvi Jaiswal", "Virat Kohli", "Shreyas Iyer", "KL Rahul",
                               "Shubman Gill", "Ravindra Jadeja", "Axar Patel", "Kuldeep Yadav", "Jasprit Bumrah", "Mohammed Siraj"],
                bowlers: ["Jasprit Bumrah", "Mohammed Siraj", "Kuldeep Yadav", "Ravindra Jadeja", "Axar Patel"]),
            MatchSimulation.Side(
                team: australia,
                battingOrder: ["Travis Head", "Mitchell Marsh", "Steve Smith", "Marnus Labuschagne", "Glenn Maxwell",
                               "Alex Carey", "Cameron Green", "Pat Cummins", "Mitchell Starc", "Adam Zampa", "Josh Hazlewood"],
                bowlers: ["Mitchell Starc", "Josh Hazlewood", "Pat Cummins", "Adam Zampa", "Glenn Maxwell"]),
        ]
        let now = Date()
        let sim = MatchSimulation(
            id: "mock-ind-aus-odi3", format: .odi, title: "3rd ODI", series: "Australia tour of India",
            venue: "Wankhede Stadium, Mumbai", sides: sides, battingFirst: 1,
            toss: "Australia won the toss and chose to bat", startDate: now.addingTimeInterval(-5 * 3600), seed: 42)

        var first = MatchSimulation.Innings(battingSide: 1)
        first.runs = 241; first.wickets = 8; first.legalBalls = 300

        var chase = MatchSimulation.Innings(battingSide: 0)
        chase.runs = 184; chase.wickets = 4; chase.legalBalls = 194
        chase.batters = [
            .init(name: "Rohit Sharma", runs: 24, balls: 27, fours: 3, sixes: 1, isOut: true),
            .init(name: "Yashasvi Jaiswal", runs: 11, balls: 19, fours: 1, sixes: 0, isOut: true),
            .init(name: "Virat Kohli", runs: 72, balls: 81, fours: 6, sixes: 1),
            .init(name: "Shreyas Iyer", runs: 18, balls: 20, fours: 2, sixes: 0, isOut: true),
            .init(name: "KL Rahul", runs: 4, balls: 8, fours: 0, sixes: 0, isOut: true),
            .init(name: "Shubman Gill", runs: 43, balls: 39, fours: 5, sixes: 0),
        ]
        chase.striker = 2
        chase.nonStriker = 5
        chase.nextInLineup = 6
        chase.bowlers = [
            .init(name: "Mitchell Starc", balls: 42, maidens: 0, runs: 41, wickets: 1),
            .init(name: "Josh Hazlewood", balls: 42, maidens: 1, runs: 29, wickets: 0),
            .init(name: "Pat Cummins", balls: 38, maidens: 0, runs: 34, wickets: 2),
            .init(name: "Adam Zampa", balls: 42, maidens: 0, runs: 38, wickets: 1),
            .init(name: "Glenn Maxwell", balls: 30, maidens: 0, runs: 30, wickets: 0),
        ]
        chase.currentBowler = 2
        chase.lastBowler = 3
        chase.bowlerBeforeLast = 2
        chase.runsThisOver = 3
        chase.partnership = Partnership(runs: 81, balls: 68)
        chase.lastWicket = "KL Rahul 4 (8)"
        chase.sequence = 8
        let outcomes: [(Delivery.Outcome, Int)] = [(.runs(1), 31), (.dot, 31), (.four, 31), (.runs(1), 31), (.dot, 31),
                                                   (.dot, 31), (.runs(2), 32), (.runs(1), 32)]
        chase.deliveries = outcomes.enumerated().map { i, item in
            Delivery(id: "mock-ind-aus-odi3-seed-\(i)", outcome: item.0, over: item.1)
        }
        sim.install(innings: [first, chase])
        // Guarantee the demo shows a boundary, a wicket and a six within the first minute or two.
        sim.scriptedOutcomes = [.dot, .runs(1), .four, .dot, .wicket, .runs(2), .wide(1), .six]
        sim.ballInterval = 9...18
        return sim
    }

    /// South Africa batting first in a T20I, ~11 overs in.
    static func englandSouthAfrica() -> MatchSimulation {
        let sides = [
            MatchSimulation.Side(
                team: england,
                battingOrder: ["Phil Salt", "Jos Buttler", "Will Jacks", "Harry Brook", "Liam Livingstone", "Moeen Ali",
                               "Sam Curran", "Chris Jordan", "Adil Rashid", "Jofra Archer", "Mark Wood"],
                bowlers: ["Jofra Archer", "Mark Wood", "Sam Curran", "Adil Rashid", "Liam Livingstone"]),
            MatchSimulation.Side(
                team: southAfrica,
                battingOrder: ["Quinton de Kock", "Reeza Hendricks", "Aiden Markram", "Heinrich Klaasen", "David Miller",
                               "Tristan Stubbs", "Marco Jansen", "Keshav Maharaj", "Kagiso Rabada", "Anrich Nortje", "Tabraiz Shamsi"],
                bowlers: ["Kagiso Rabada", "Marco Jansen", "Anrich Nortje", "Keshav Maharaj", "Tabraiz Shamsi"]),
        ]
        let sim = MatchSimulation(
            id: "mock-eng-sa-t20-2", format: .t20, title: "2nd T20I", series: "South Africa tour of England",
            venue: "Lord's, London", sides: sides, battingFirst: 1,
            toss: "England won the toss and chose to bowl", startDate: Date().addingTimeInterval(-50 * 60), seed: 7)
        sim.fastForward(balls: 72)
        sim.ballInterval = 12...26
        return sim
    }

    /// Starts 42 minutes after launch, then goes live on its own.
    static func pakistanNewZealand() -> MatchSimulation {
        let sides = [
            MatchSimulation.Side(
                team: pakistan,
                battingOrder: ["Saim Ayub", "Mohammad Rizwan", "Babar Azam", "Fakhar Zaman", "Iftikhar Ahmed", "Shadab Khan",
                               "Imad Wasim", "Shaheen Afridi", "Naseem Shah", "Haris Rauf", "Abrar Ahmed"],
                bowlers: ["Shaheen Afridi", "Naseem Shah", "Haris Rauf", "Shadab Khan", "Abrar Ahmed"]),
            MatchSimulation.Side(
                team: newZealand,
                battingOrder: ["Devon Conway", "Finn Allen", "Rachin Ravindra", "Daryl Mitchell", "Glenn Phillips",
                               "Mark Chapman", "Mitchell Santner", "Kyle Jamieson", "Ish Sodhi", "Tim Southee", "Lockie Ferguson"],
                bowlers: ["Tim Southee", "Lockie Ferguson", "Kyle Jamieson", "Mitchell Santner", "Ish Sodhi"]),
        ]
        return MatchSimulation(
            id: "mock-pak-nz-t20-1", format: .t20, title: "1st T20I", series: "New Zealand tour of Pakistan",
            venue: "National Stadium, Karachi", sides: sides, battingFirst: 0,
            toss: "Pakistan won the toss and chose to bat", startDate: Date().addingTimeInterval(42 * 60), seed: 99)
    }

    static func sriLankaBangladeshResult(now: Date) -> CricketMatch {
        CricketMatch(
            id: "mock-sl-ban-t20-3", teams: [sriLanka, bangladesh], format: .t20, title: "3rd T20I",
            series: "Bangladesh tour of Sri Lanka", venue: "R. Premadasa Stadium, Colombo", status: .completed,
            statusText: "Sri Lanka won by 5 wickets", startDate: now.addingTimeInterval(-6 * 3600),
            innings: [InningsScore(team: bangladesh, runs: 187, wickets: 9, legalBalls: 120),
                      InningsScore(team: sriLanka, runs: 191, wickets: 5, legalBalls: 116)],
            target: 188, result: "Sri Lanka won by 5 wickets", toss: "Sri Lanka won the toss and chose to bowl")
    }

    static func upcoming(startingAt start: Date) -> CricketMatch {
        CricketMatch(
            id: "mock-pak-nz-t20-1", teams: [pakistan, newZealand], format: .t20, title: "1st T20I",
            series: "New Zealand tour of Pakistan", venue: "National Stadium, Karachi", status: .upcoming,
            statusText: "Starts \(start.formatted(date: .omitted, time: .shortened))", startDate: start,
            innings: [], target: nil, result: nil, toss: nil)
    }

    static func completed(now: Date) -> Scorecard {
        let match = CricketMatch(
            id: "mock-ind-aus-odi3", teams: [india, australia], format: .odi, title: "3rd ODI",
            series: "Australia tour of India", venue: "Wankhede Stadium, Mumbai", status: .completed,
            statusText: "India won by 6 wickets", startDate: now.addingTimeInterval(-8 * 3600),
            innings: [InningsScore(team: australia, runs: 241, wickets: 8, legalBalls: 300),
                      InningsScore(team: india, runs: 242, wickets: 4, legalBalls: 267)],
            target: 242, result: "India won by 6 wickets", toss: "Australia won the toss and chose to bat")
        return Scorecard(
            match: match,
            batters: [Batter(name: "Virat Kohli", runs: 104, balls: 112, fours: 9, sixes: 2, isStriker: false),
                      Batter(name: "Shubman Gill", runs: 61, balls: 58, fours: 7, sixes: 1, isStriker: false)],
            bowler: nil, recentBalls: [], partnership: nil, lastWicket: "KL Rahul 4 (8)",
            currentRunRate: 5.44, requiredRunRate: nil, target: 242, runsRequired: nil, ballsRemaining: nil)
    }

    static func inningsBreak(from sim: MatchSimulation, now: Date) -> Scorecard {
        var match = sim.matchSnapshot(now: now)
        let first = match.innings.first ?? InningsScore(team: australia, runs: 241, wickets: 8, legalBalls: 300)
        match.innings = [first]
        match.status = .inningsBreak
        match.target = first.runs + 1
        let chasing = first.team == match.teamA ? match.teamB : match.teamA
        match.statusText = "Innings break · \(chasing.shortName) need \(first.runs + 1) to win"
        return Scorecard(match: match, batters: [], bowler: nil, recentBalls: [], partnership: nil, lastWicket: nil,
                         currentRunRate: Double(first.runs) * 6 / Double(max(first.legalBalls, 1)),
                         requiredRunRate: nil, target: first.runs + 1, runsRequired: nil, ballsRemaining: nil)
    }

    static func rainDelay(from sim: MatchSimulation, now: Date) -> Scorecard {
        var card = sim.scorecardSnapshot(now: now)
        card.match.status = .rainDelay
        card.match.statusText = "Rain has stopped play · covers on"
        return card
    }

    static func emptyScorecard(for match: CricketMatch) -> Scorecard {
        Scorecard(match: match, batters: [], bowler: nil, recentBalls: [], partnership: nil, lastWicket: nil,
                  currentRunRate: nil, requiredRunRate: nil, target: match.target, runsRequired: nil, ballsRemaining: nil)
    }

    /// Next 7:30 PM local time.
    static func nextEvening(after now: Date) -> Date {
        let calendar = Calendar.current
        let today = calendar.date(bySettingHour: 19, minute: 30, second: 0, of: now) ?? now
        return today > now.addingTimeInterval(3600) ? today : calendar.date(byAdding: .day, value: 1, to: today) ?? today
    }
}
