import Foundation

/// Real ball-by-ball data from your own Cricket Live server (the `server/` folder in this repo).
///
/// The server does all polling of the upstream data source once, for everyone; this app
/// just reads the server's JSON. No API key is needed on the user's Mac.
///
///     GET {base}/api/matches         → [match]
///     GET {base}/api/matches/{id}    → scorecard (match, batters, bowler, recent balls…)
struct ServerScoreProvider: CricketScoreProvider {
    let baseURL: URL

    var displayName: String { "Cricket Live" }

    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = ["Accept": "application/json"]
        return URLSession(configuration: config)
    }()

    func fetchLiveMatches() async throws -> [CricketMatch] {
        let dtos: [ServerMatch] = try await get("api/matches")
        return dtos.map(\.model)
    }

    func fetchScorecard(matchID: String) async throws -> Scorecard {
        let dto: ServerScorecard = try await get("api/matches/\(matchID)")
        return dto.model
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw CricketAPIError.invalidResponse }
        if http.statusCode == 404 { throw CricketAPIError.matchNotFound }
        guard (200..<300).contains(http.statusCode) else { throw CricketAPIError.http(status: http.statusCode) }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw CricketAPIError.decoding
        }
    }
}

// MARK: - Server JSON

private struct ServerTeam: Decodable {
    let id: String
    let name: String
    let short: String
}

private struct ServerInnings: Decodable {
    let teamId: String
    let runs: Int
    let wickets: Int
    let balls: Int
}

struct ServerMatch: Decodable {
    let id: String
    let series: String?
    let title: String?
    let format: String?
    let venue: String?
    let startDate: String?
    let status: String
    let statusText: String?
    fileprivate let teams: [ServerTeam]
    fileprivate let innings: [ServerInnings]
    let target: Int?
    let result: String?

    var model: CricketMatch {
        let resolved = teams.map { Team(name: $0.name, shortName: $0.short) }
        let byID = Dictionary(zip(teams.map(\.id), resolved), uniquingKeysWith: { a, _ in a })
        return CricketMatch(
            id: id,
            teams: resolved.isEmpty ? [.unknown, .unknown] : resolved,
            format: MatchFormat(rawValue: format ?? "") ?? .other,
            title: title ?? "",
            series: series ?? "",
            venue: venue ?? "",
            status: MatchStatus(rawValue: status) ?? .live,
            statusText: statusText ?? "",
            startDate: startDate.flatMap(Self.parseDate),
            innings: innings.map {
                InningsScore(team: byID[$0.teamId] ?? resolved.first ?? .unknown,
                             runs: $0.runs, wickets: $0.wickets, legalBalls: $0.balls)
            },
            target: target,
            result: result,
            toss: nil
        )
    }

    private static func parseDate(_ string: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}

private struct ServerBatter: Decodable {
    let name: String
    let runs: Int
    let balls: Int
    let fours: Int
    let sixes: Int
    let isStriker: Bool
}

private struct ServerBowler: Decodable {
    let name: String
    let balls: Int
    let maidens: Int
    let runs: Int
    let wickets: Int
}

private struct ServerBall: Decodable {
    struct Outcome: Decodable {
        let type: String
        let runs: Int
    }
    let id: String
    let outcome: Outcome
    let over: Int?

    var model: Delivery {
        let n = outcome.runs
        let mapped: Delivery.Outcome = switch outcome.type {
        case "dot": .dot
        case "four": .four
        case "six": .six
        case "wicket": .wicket
        case "wide": .wide(max(n, 1))
        case "noBall": .noBall(max(n, 1))
        case "bye": .bye(n)
        case "legBye": .legBye(n)
        default: n == 0 ? .dot : .runs(n)
        }
        return Delivery(id: id, outcome: mapped, over: over)
    }
}

struct ServerScorecard: Decodable {
    let match: ServerMatch
    fileprivate let batters: [ServerBatter]
    fileprivate let bowler: ServerBowler?
    fileprivate let recentBalls: [ServerBall]
    let lastWicket: String?
    let currentRunRate: Double?
    let requiredRunRate: Double?
    let target: Int?
    let runsRequired: Int?
    let ballsRemaining: Int?

    var model: Scorecard {
        Scorecard(
            match: match.model,
            batters: batters.map {
                Batter(name: $0.name, runs: $0.runs, balls: $0.balls, fours: $0.fours, sixes: $0.sixes, isStriker: $0.isStriker)
            },
            bowler: bowler.map {
                Bowler(name: $0.name, legalBalls: $0.balls, maidens: $0.maidens, runs: $0.runs, wickets: $0.wickets)
            },
            recentBalls: recentBalls.map(\.model),
            partnership: nil,
            lastWicket: lastWicket,
            currentRunRate: currentRunRate,
            requiredRunRate: requiredRunRate,
            target: target,
            runsRequired: runsRequired,
            ballsRemaining: ballsRemaining
        )
    }
}
