import Foundation

/// Real data from CricketData.org (https://cricketdata.org — formerly CricAPI).
///
/// The API key is never stored in source. It is resolved at request time from:
///   1. the `CRICKET_API_KEY` environment variable (handy in Xcode: Scheme → Run → Environment), or
///   2. the macOS Keychain (entered in Settings → Data).
///
/// Free plans allow ~100 requests/day, so this provider only refreshes the match
/// list every few minutes and otherwise fetches just the selected scorecard.
/// Their free tier has no ball-by-ball feed, so "Recent balls" is hidden for real data.
struct LiveCricketScoreProvider: CricketScoreProvider {
    var displayName: String { "CricketData.org" }
    var minimumListRefreshInterval: TimeInterval { 300 }

    private let baseURL = URL(string: "https://api.cricapi.com/v1/")!
    private let session: URLSession
    private let apiKey: @Sendable () -> String?

    init(apiKey: @escaping @Sendable () -> String? = { APIKeyStore.resolvedKey() }) {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = ["Accept": "application/json"]
        config.waitsForConnectivity = false
        self.session = URLSession(configuration: config)
        self.apiKey = apiKey
    }

    func fetchLiveMatches() async throws -> [CricketMatch] {
        let response: CDResponse<[CDMatch]> = try await get("currentMatches", query: ["offset": "0"])
        return (response.data ?? []).map(\.model)
    }

    func fetchScorecard(matchID: String) async throws -> Scorecard {
        let data = try await getData("match_scorecard", query: ["id": matchID])
        let decoder = JSONDecoder()
        guard let summary = try? decoder.decode(CDResponse<CDMatch>.self, from: data).data else {
            throw CricketAPIError.matchNotFound
        }
        let card = (try? decoder.decode(CDResponse<CDScorecard>.self, from: data).data?.scorecard) ?? []
        return Self.scorecard(match: summary.model, innings: card)
    }

    // MARK: Networking

    private func get<T: Decodable>(_ path: String, query: [String: String]) async throws -> CDResponse<T> {
        let data = try await getData(path, query: query)
        do {
            return try JSONDecoder().decode(CDResponse<T>.self, from: data)
        } catch {
            throw CricketAPIError.decoding
        }
    }

    private func getData(_ path: String, query: [String: String]) async throws -> Data {
        guard let key = apiKey(), !key.isEmpty else { throw CricketAPIError.missingAPIKey }
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "apikey", value: key)]
            + query.map { URLQueryItem(name: $0.key, value: $0.value) }
        let (data, response) = try await session.data(from: components.url!)
        guard let http = response as? HTTPURLResponse else { throw CricketAPIError.invalidResponse }
        if http.statusCode == 429 { throw CricketAPIError.rateLimited }
        guard (200..<300).contains(http.statusCode) else { throw CricketAPIError.http(status: http.statusCode) }

        // The API reports failures as HTTP 200 + {"status":"failure","reason":"..."}.
        if let envelope = try? JSONDecoder().decode(CDEnvelope.self, from: data), envelope.status == "failure" {
            let reason = envelope.reason ?? "Request failed"
            let lower = reason.lowercased()
            if lower.contains("hits") || lower.contains("limit") { throw CricketAPIError.rateLimited }
            if lower.contains("key") { throw CricketAPIError.provider(message: "Invalid API key — check Settings → Data") }
            throw CricketAPIError.provider(message: reason)
        }
        return data
    }

    // MARK: Mapping

    static func scorecard(match: CricketMatch, innings: [CDInningsCard]) -> Scorecard {
        let current = innings.last
        let batting = (current?.batting ?? []).filter {
            let dismissal = ($0.dismissalText ?? "").lowercased()
            return dismissal.isEmpty || dismissal.contains("not out") || dismissal == "batting"
        }
        let batters = match.status.isInProgress ? batting.suffix(2).map {
            Batter(name: $0.batsman?.name ?? "Batter", runs: $0.r ?? 0, balls: $0.b ?? 0,
                   fours: $0.fours ?? 0, sixes: $0.sixes ?? 0, isStriker: false)
        } : []
        let bowler = match.status.isInProgress ? current?.bowling?.last.map {
            Bowler(name: $0.bowler?.name ?? "Bowler", legalBalls: Overs.balls(fromOvers: $0.o ?? 0),
                   maidens: $0.m ?? 0, runs: $0.r ?? 0, wickets: $0.w ?? 0)
        } : nil

        let inn = match.currentInnings
        let crr = inn.flatMap { $0.legalBalls > 0 ? Double($0.runs) * 6 / Double($0.legalBalls) : nil }
        var rrr: Double?, need: Int?, left: Int?
        if match.status.isInProgress, let target = match.target, let inn, let overs = match.format.oversPerInnings,
           match.innings.count >= 2 {
            need = max(0, target - inn.runs)
            left = max(0, overs * 6 - inn.legalBalls)
            if let need, let left, left > 0 { rrr = Double(need) * 6 / Double(left) }
        }

        return Scorecard(match: match, batters: Array(batters), bowler: bowler, recentBalls: [], partnership: nil,
                         lastWicket: nil, currentRunRate: crr, requiredRunRate: rrr, target: match.target,
                         runsRequired: need, ballsRemaining: left)
    }
}

// MARK: - Provider selection

enum DataSource: String, CaseIterable, Identifiable, Sendable {
    case espn, liveServer, demo, cricketData

    var id: String { rawValue }
    var title: String {
        switch self {
        case .espn: "Live — ESPNcricinfo (ball-by-ball, no key)"
        case .liveServer: "Your own Cricket Live server"
        case .demo: "Demo data (simulated)"
        case .cricketData: "CricketData.org (your own API key)"
        }
    }
}

enum ProviderFactory {
    /// ── The one place that decides where scores come from. ──
    /// Add a new case to `DataSource` and a provider here to plug in another API.
    static func make(for source: DataSource, serverURL: URL? = nil) -> CricketScoreProvider {
        switch source {
        case .espn: ESPNScoreProvider()
        case .liveServer: ServerScoreProvider(baseURL: serverURL ?? AppSettings.defaultServerURL)
        case .demo: MockCricketScoreProvider()
        case .cricketData: LiveCricketScoreProvider()
        }
    }
}

// MARK: - CricketData.org DTOs

private struct CDEnvelope: Decodable {
    let status: String?
    let reason: String?
}

struct CDResponse<T: Decodable>: Decodable {
    let status: String?
    let data: T?
}

struct CDMatch: Decodable {
    let id: String
    let name: String?
    let matchType: String?
    let status: String?
    let venue: String?
    let dateTimeGMT: String?
    let teams: [String]?
    let teamInfo: [CDTeamInfo]?
    let score: [CDScore]?
    let matchStarted: Bool?
    let matchEnded: Bool?
    let tossWinner: String?
    let tossChoice: String?

    struct CDTeamInfo: Decodable {
        let name: String?
        let shortname: String?
    }

    struct CDScore: Decodable {
        let r: Int?
        let w: Int?
        let o: Double?
        let inning: String?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            r = c.lenientInt(.r); w = c.lenientInt(.w); o = c.lenientDouble(.o)
            inning = try? c.decode(String.self, forKey: .inning)
        }
        enum CodingKeys: String, CodingKey { case r, w, o, inning }
    }

    var model: CricketMatch {
        let names = teams ?? teamInfo?.compactMap(\.name) ?? []
        let resolvedTeams = names.map { name in
            Team(name: name, shortName: teamInfo?.first { $0.name == name }?.shortname?.uppercased())
        }
        let format = MatchFormat(rawValue: (matchType ?? "").lowercased()) ?? .other
        let innings: [InningsScore] = (score ?? []).map { s in
            let label = (s.inning ?? "").lowercased()
            let team = resolvedTeams.first { label.hasPrefix($0.name.lowercased()) } ?? resolvedTeams.first ?? .unknown
            return InningsScore(team: team, runs: s.r ?? 0, wickets: s.w ?? 0, legalBalls: Overs.balls(fromOvers: s.o ?? 0))
        }
        let text = status ?? ""
        let lower = text.lowercased()
        let mappedStatus: MatchStatus
        if matchEnded == true {
            mappedStatus = lower.contains("abandon") || lower.contains("no result") ? .abandoned : .completed
        } else if matchStarted != true {
            mappedStatus = .upcoming
        } else if lower.contains("rain") || lower.contains("delay") || lower.contains("wet outfield") {
            mappedStatus = .rainDelay
        } else if lower.contains("innings break") || lower.contains("stumps") || lower.contains("lunch") || lower.contains("tea") {
            mappedStatus = .inningsBreak
        } else {
            mappedStatus = .live
        }

        // "India vs Australia, 3rd ODI, Australia tour of India" → title "3rd ODI", series "Australia tour of India"
        let parts = (name ?? "").components(separatedBy: ", ")
        let title = parts.count > 1 ? parts[1] : format.displayName
        let series = parts.count > 2 ? parts[2...].joined(separator: ", ") : ""

        var target: Int?
        if format.oversPerInnings != nil, innings.count >= 2 { target = innings[0].runs + 1 }
        let toss = tossWinner.map { winner in
            "\(winner.capitalized) won the toss" + (tossChoice.map { " and chose to \($0)" } ?? "")
        }

        return CricketMatch(
            id: id,
            teams: resolvedTeams.isEmpty ? [.unknown, .unknown] : resolvedTeams,
            format: format,
            title: title,
            series: series,
            venue: venue ?? "",
            status: mappedStatus,
            statusText: text,
            startDate: dateTimeGMT.flatMap(Self.parseGMT),
            innings: innings,
            target: target,
            result: mappedStatus == .completed || mappedStatus == .abandoned ? text : nil,
            toss: toss
        )
    }

    private static func parseGMT(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.date(from: string)
    }
}

struct CDScorecard: Decodable {
    let scorecard: [CDInningsCard]?
}

struct CDInningsCard: Decodable {
    let batting: [CDBatting]?
    let bowling: [CDBowling]?
    let inning: String?
}

struct CDPlayer: Decodable {
    let name: String?
}

struct CDBatting: Decodable {
    let batsman: CDPlayer?
    let dismissalText: String?
    let r: Int?, b: Int?, fours: Int?, sixes: Int?

    enum CodingKeys: String, CodingKey {
        case batsman, r, b
        case dismissalText = "dismissal-text"
        case fours = "4s"
        case sixes = "6s"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        batsman = try? c.decode(CDPlayer.self, forKey: .batsman)
        dismissalText = try? c.decode(String.self, forKey: .dismissalText)
        r = c.lenientInt(.r); b = c.lenientInt(.b); fours = c.lenientInt(.fours); sixes = c.lenientInt(.sixes)
    }
}

struct CDBowling: Decodable {
    let bowler: CDPlayer?
    let o: Double?
    let m: Int?, r: Int?, w: Int?

    enum CodingKeys: String, CodingKey { case bowler, o, m, r, w }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bowler = try? c.decode(CDPlayer.self, forKey: .bowler)
        o = c.lenientDouble(.o); m = c.lenientInt(.m); r = c.lenientInt(.r); w = c.lenientInt(.w)
    }
}

private extension KeyedDecodingContainer {
    /// Accepts 12, 12.0 or "12".
    func lenientInt(_ key: Key) -> Int? {
        if let v = try? decode(Int.self, forKey: key) { return v }
        if let v = try? decode(Double.self, forKey: key), v.isFinite { return Int(v) }
        if let s = try? decode(String.self, forKey: key) { return Int(s) ?? Double(s).map { Int($0) } }
        return nil
    }

    func lenientDouble(_ key: Key) -> Double? {
        if let v = try? decode(Double.self, forKey: key), v.isFinite { return v }
        if let s = try? decode(String.self, forKey: key), let v = Double(s), v.isFinite { return v }
        return nil
    }
}
