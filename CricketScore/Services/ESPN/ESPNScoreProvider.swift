import Foundation

/// Live ball-by-ball scores straight from ESPNcricinfo's public JSON feed.
///
/// No server and no API key: each Mac reads the same public endpoints ESPN's own website
/// uses, with polite polling (the app's refresh interval, only while a match is live).
/// The feed is unofficial — fine for a free, non-commercial app that credits ESPNcricinfo.
/// Swap this provider for a licensed one before going commercial (see ProviderFactory).
actor ESPNScoreProvider: CricketScoreProvider {
    nonisolated var displayName: String { "ESPNcricinfo" }

    private let scorepanelURL = URL(string: "https://site.api.espn.com/apis/site/v2/sports/cricket/scorepanel")!
    private let session: URLSession
    private var leagueByMatch: [String: String] = [:]
    private var pageCounts: [String: Int] = [:]
    private var lastList: (at: Date, matches: [CricketMatch])?
    /// Which in-progress matches have a ball-by-ball feed (probed once, cached 10 minutes).
    private var coverage: [String: (has: Bool, at: Date)] = [:]

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpAdditionalHeaders = ["Accept": "application/json"]
        session = URLSession(configuration: config)
    }

    // MARK: CricketScoreProvider

    func fetchLiveMatches() async throws -> [CricketMatch] {
        if let last = lastList, Date().timeIntervalSince(last.at) < 8 { return last.matches }
        let json = try await getJSON(scorepanelURL)
        var matches: [(match: CricketMatch, international: Bool)] = []
        for group in json.arr("scores") {
            let league = group.arr("leagues").first ?? [:]
            for event in group.arr("events") {
                guard let parsed = Self.parseEvent(event, league: league) else { continue }
                leagueByMatch[parsed.match.id] = parsed.leagueID
                matches.append((parsed.match, parsed.international))
            }
        }
        // Probe coverage for in-progress matches we haven't checked recently (one request each).
        let toProbe = matches.map(\.match).filter {
            $0.status.isInProgress && Date().timeIntervalSince(coverage[$0.id]?.at ?? .distantPast) > 600
        }.prefix(8)
        if !toProbe.isEmpty {
            await withTaskGroup(of: (String, Bool?).self) { group in
                for match in toProbe {
                    guard let league = leagueByMatch[match.id] else { continue }
                    group.addTask { [self] in (match.id, try? await self.probe(league: league, matchID: match.id)) }
                }
                for await (id, has) in group { if let has { coverage[id] = (has, Date()) } }
            }
        }
        for i in matches.indices { matches[i].match.hasBallByBall = coverage[matches[i].match.id]?.has }

        let sorted = matches.sorted { a, b in
            if a.match.status.sortRank != b.match.status.sortRank { return a.match.status.sortRank < b.match.status.sortRank }
            let ca = a.match.hasBallByBall != false, cb = b.match.hasBallByBall != false
            if ca != cb { return ca }
            if a.international != b.international { return a.international }
            return (a.match.startDate ?? .distantFuture) < (b.match.startDate ?? .distantFuture)
        }.map(\.match)
        lastList = (Date(), sorted)
        return sorted
    }

    func fetchScorecard(matchID: String) async throws -> Scorecard {
        var match = lastList?.matches.first { $0.id == matchID }
        if match == nil || leagueByMatch[matchID] == nil {
            match = try await fetchLiveMatches().first { $0.id == matchID }
        }
        guard var match, let league = leagueByMatch[matchID] else { throw CricketAPIError.matchNotFound }
        guard match.status != .upcoming else { return Self.emptyScorecard(match) }

        let balls = try await fetchRecentBalls(league: league, matchID: matchID)
        guard balls.count > 1 || balls.contains(where: { !$0.text.isEmpty }) else {
            coverage[matchID] = (false, Date())
            match.hasBallByBall = false
            return Self.emptyScorecard(match)
        }
        coverage[matchID] = (true, Date())
        match.hasBallByBall = true
        match = Self.merge(match, balls: balls)
        return Self.scorecard(match, balls: balls)
    }

    /// Does this match have a ball-by-ball feed? (First commentary page has real deliveries.)
    private func probe(league: String, matchID: String) async throws -> Bool {
        let page = try await commentaryPage(league: league, matchID: matchID, page: nil)
        return page.balls.contains { !$0.text.isEmpty }
    }

    // MARK: Networking

    private func getJSON(_ url: URL) async throws -> [String: Any] {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw CricketAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw CricketAPIError.http(status: http.statusCode) }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CricketAPIError.decoding }
        return json
    }

    private func commentaryPage(league: String, matchID: String, page: Int?) async throws -> (pageCount: Int, balls: [Ball]) {
        var components = URLComponents(string: "https://site.web.api.espn.com/apis/site/v2/sports/cricket/\(league)/playbyplay")!
        components.queryItems = [URLQueryItem(name: "event", value: matchID)] + (page.map { [URLQueryItem(name: "page", value: String($0))] } ?? [])
        let json = try await getJSON(components.url!)
        let commentary = json.dict("commentary") ?? [:]
        return (max(1, commentary.int("pageCount") ?? 1), commentary.arr("items").compactMap(Ball.init))
    }

    /// Newest page (+ the one before it when needed): usually one request per refresh.
    private func fetchRecentBalls(league: String, matchID: String) async throws -> [Ball] {
        var pages: [[Ball]] = []
        var pageCount: Int
        if let known = pageCounts[matchID] {
            let last = try await commentaryPage(league: league, matchID: matchID, page: known)
            pages.append(last.balls)
            pageCount = known
            if last.pageCount > known {
                pageCount = last.pageCount
                pages.append(try await commentaryPage(league: league, matchID: matchID, page: pageCount).balls)
            }
        } else {
            let first = try await commentaryPage(league: league, matchID: matchID, page: nil)
            pageCount = first.pageCount
            pages.append(pageCount == 1 ? first.balls : try await commentaryPage(league: league, matchID: matchID, page: pageCount).balls)
        }
        pageCounts[matchID] = pageCount
        if pages.joined().count < 12, pageCount > 1 {
            pages.append(try await commentaryPage(league: league, matchID: matchID, page: pageCount - 1).balls)
        }
        var byID: [String: Ball] = [:]
        for ball in pages.joined() { byID[ball.id] = ball }
        return byID.values.sorted { $0.sequence < $1.sequence }
    }

    // MARK: Parsing: matches

    static func parseEvent(_ event: [String: Any], league: [String: Any]) -> (match: CricketMatch, leagueID: String, international: Bool)? {
        guard let id = event.string("id") else { return nil }
        let comp = event.arr("competitions").first ?? [:]
        let competitors = comp.arr("competitors").sorted { ($0.int("order") ?? 0) < ($1.int("order") ?? 0) }
        let teamIDs = competitors.map { $0.dict("team")?.string("id") ?? "" }
        let teams = competitors.map { c -> Team in
            let t = c.dict("team") ?? [:]
            let name = decodeEntities(t.string("displayName") ?? t.string("name") ?? "TBC")
            return Team(name: name, shortName: t.string("abbreviation"))
        }

        var innings: [(period: Int, score: InningsScore)] = []
        for (index, c) in competitors.enumerated() {
            for ls in c.arr("linescores") where ls.bool("isBatting") == true {
                innings.append((ls.int("period") ?? innings.count + 1,
                                InningsScore(team: teams[index], runs: ls.int("runs") ?? 0, wickets: ls.int("wickets") ?? 0,
                                             legalBalls: Overs.balls(fromOvers: ls.double("overs") ?? 0))))
            }
        }
        innings.sort { $0.period < $1.period }
        _ = teamIDs

        let cls = comp.dict("class") ?? [:]
        let card = cls.string("generalClassCard") ?? cls.string("eventType") ?? ""
        let format = mapFormat(card)
        let statusType = (event.dict("status") ?? [:]).dict("type") ?? [:]
        let summary = decodeEntities((comp.dict("status")?.string("summary") ?? event.dict("status")?.string("summary") ?? ""))
            .trimmingCharacters(in: .whitespaces)
        var status = mapStatus(statusType, summary: summary)
        if status == .live, innings.isEmpty, summary.range(of: "starts at|yet to begin|scheduled", options: [.regularExpression, .caseInsensitive]) != nil {
            status = .upcoming
        }
        let intlID = cls.string("internationalClassId") ?? ""
        let international = ["Test", "ODI", "T20I", "WODI", "WT20I"].contains(card) || (!intlID.isEmpty && intlID != "0")

        var target: Int?
        if format.oversPerInnings != nil, innings.count >= 2 { target = innings[0].score.runs + 1 }

        let match = CricketMatch(
            id: id,
            teams: teams.isEmpty ? [.unknown, .unknown] : teams,
            format: format,
            title: comp.string("description") ?? "",
            series: decodeEntities(league.string("name") ?? ""),
            venue: comp.dict("venue")?.string("fullName") ?? "",
            status: status,
            statusText: summary.isEmpty ? (statusType.string("description") ?? "") : summary,
            startDate: event.string("date").flatMap(parseDate),
            innings: innings.map(\.score),
            target: target,
            result: status == .completed || status == .abandoned ? summary : nil,
            toss: nil
        )
        return (match, league.string("id") ?? "", international)
    }

    static func mapStatus(_ type: [String: Any], summary: String) -> MatchStatus {
        let state = type.string("state") ?? ""
        let desc = "\(type.string("description") ?? "") \(type.string("detail") ?? "")".lowercased()
        if state == "pre" { return .upcoming }
        if state == "post" {
            return "\(desc) \(summary.lowercased())".range(of: "abandon|no result|cancel", options: .regularExpression) != nil ? .abandoned : .completed
        }
        if desc.range(of: "rain|delay|bad light|wet|weather", options: .regularExpression) != nil { return .rainDelay }
        if desc.range(of: "innings break|stumps|lunch|tea|drinks|break", options: .regularExpression) != nil { return .inningsBreak }
        return .live
    }

    static func mapFormat(_ card: String) -> MatchFormat {
        let c = card.uppercased()
        if c.contains("TEST") || c.contains("FIRST-CLASS") { return .test }
        if c.contains("T10") { return .t10 }
        if c.contains("T20") || c.contains("HUNDRED") { return .t20 }
        if c.contains("ODI") || c.contains("LIST A") { return .odi }
        return .other
    }

    private static func parseDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        for format in ["yyyy-MM-dd'T'HH:mm'Z'", "yyyy-MM-dd'T'HH:mm:ss'Z'"] {
            f.dateFormat = format
            if let d = f.date(from: s) { return d }
        }
        return ISO8601DateFormatter().date(from: s)
    }

    // MARK: Parsing: balls

    struct PlayerLine {
        let name: String
        let runs: Int, balls: Int, fours: Int, sixes: Int
    }

    struct BowlerLine {
        let name: String
        let balls: Int, maidens: Int, runs: Int, wickets: Int
    }

    struct Ball {
        let id: String
        let sequence: Int
        let inningsNumber: Int
        let teamShort: String
        let over: Int
        let outcome: Delivery.Outcome
        let runsOffBall: Int
        let text: String
        let dismissal: String
        let batter: PlayerLine?
        let otherBatter: PlayerLine?
        let bowler: BowlerLine?
        // Innings state after this ball
        let runs: Int, wickets: Int, legalBalls: Int
        let target: Int?, runRate: Double?, requiredRate: Double?, remainingRuns: Int?, remainingBalls: Int?, ballLimit: Int?

        init?(_ item: [String: Any]) {
            guard let seq = item.int("sequence") else { return nil }
            // Before a day's play / new innings ESPN posts an empty placeholder (no text, no batter,
            // over 0). It isn't a delivery, so it must not become the "latest ball".
            // (It carries empty player objects — `athlete: {}` — so check for a real player.)
            let hasText = !((item.string("shortText") ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
            guard hasText || Self.isPlayer(item.dict("batsman")?.dict("athlete")) || Self.isPlayer(item.dict("bowler")?.dict("athlete")) else { return nil }
            sequence = seq
            id = String(seq)
            let inn = item.dict("innings") ?? [:]
            let over = item.dict("over") ?? [:]
            inningsNumber = inn.int("number") ?? item.int("period") ?? 1
            teamShort = item.dict("team")?.string("abbreviation") ?? ""
            self.over = max(0, (over.int("number") ?? 1) - 1)
            text = decodeEntities(item.string("shortText") ?? "").trimmingCharacters(in: .whitespaces)
            let dismissed = item.dict("dismissal")?.bool("dismissal") == true
            dismissal = dismissed ? decodeEntities(item.dict("dismissal")?.string("text") ?? "") : ""

            let typeID = (item.dict("playType") ?? [:]).string("id") ?? ""
            let desc = ((item.dict("playType") ?? [:]).string("description") ?? "").lowercased()
            let value = item.int("scoreValue") ?? 0
            runsOffBall = value
            if dismissed || typeID == "9" || desc == "out" { outcome = .wicket }
            else if typeID == "4" || desc == "six" { outcome = .six }
            else if typeID == "3" || desc == "four" { outcome = .four }
            else if typeID == "6" || desc.contains("wide") { outcome = .wide(max(value, 1)) }
            else if typeID == "5" || desc.contains("no ball") { outcome = .noBall(max(value, 1)) }
            else if typeID == "8" || desc.contains("leg bye") { outcome = .legBye(value) }
            else if typeID == "7" || desc.contains("bye") { outcome = .bye(value) }
            else if value == 0 { outcome = .dot }
            else { outcome = .runs(value) }

            func player(_ d: [String: Any]?) -> PlayerLine? {
                guard let d, let athlete = d.dict("athlete"), Self.isPlayer(athlete) else { return nil }
                return PlayerLine(name: decodeEntities(athlete.string("displayName") ?? athlete.string("name") ?? "Batter"),
                                  runs: d.int("totalRuns") ?? 0, balls: d.int("faced") ?? 0,
                                  fours: d.int("fours") ?? 0, sixes: d.int("sixes") ?? 0)
            }
            batter = player(item.dict("batsman"))
            otherBatter = player(item.dict("otherBatsman"))
            if let b = item.dict("bowler"), let athlete = b.dict("athlete"), Self.isPlayer(athlete) {
                bowler = BowlerLine(name: decodeEntities(athlete.string("displayName") ?? "Bowler"), balls: b.int("balls") ?? 0,
                                    maidens: b.int("maidens") ?? 0, runs: b.int("conceded") ?? 0, wickets: b.int("wickets") ?? 0)
            } else {
                bowler = nil
            }
            runs = inn.int("runs") ?? 0
            wickets = inn.int("wickets") ?? 0
            legalBalls = inn.int("balls") ?? 0
            target = inn.int("target").flatMap { $0 > 0 ? $0 : nil }
            runRate = inn.double("runRate")
            requiredRate = inn.double("requiredRunRate")
            remainingRuns = inn.int("remainingRuns")
            remainingBalls = inn.int("remainingBalls")
            ballLimit = inn.int("ballLimit").flatMap { $0 > 0 ? $0 : nil }
        }

        static func isPlayer(_ athlete: [String: Any]?) -> Bool {
            guard let athlete else { return false }
            return athlete.string("id") != nil || athlete.string("displayName") != nil || athlete.string("name") != nil
        }

        var isLegal: Bool {
            switch outcome {
            case .wide, .noBall: false
            default: true
            }
        }

        /// Runs physically run (decides whether the batters crossed).
        var runsRun: Int {
            switch outcome {
            case .runs(let n), .bye(let n), .legBye(let n): n
            case .wide(let n), .noBall(let n): max(0, n - 1)
            default: 0
            }
        }
    }

    // MARK: Building

    /// The newest ball is fresher than the match list: overlay its score.
    static func merge(_ match: CricketMatch, balls: [Ball]) -> CricketMatch {
        guard let latest = balls.last else { return match }
        var m = match
        let team = m.teams.first { $0.shortName == latest.teamShort } ?? m.innings.last?.team ?? m.teamA
        let updated = InningsScore(team: team, runs: latest.runs, wickets: latest.wickets, legalBalls: latest.legalBalls)
        if latest.inningsNumber - 1 < m.innings.count {
            let i = latest.inningsNumber - 1
            // ESPN's match list lags the ball feed (it can still say "innings break" / "stumps"
            // after play resumes). A ball beyond the list's score means play is on.
            if latest.legalBalls > m.innings[i].legalBalls, m.status == .inningsBreak || m.status == .rainDelay {
                m.status = .live
            }
            if latest.legalBalls >= m.innings[i].legalBalls { m.innings[i] = updated }
        } else if latest.inningsNumber - 1 == m.innings.count {
            m.innings.append(updated)
        }
        if let t = latest.target { m.target = t }
        if m.status == .live, let t = latest.target, let need = latest.remainingRuns, let left = latest.remainingBalls, t > 0 {
            m.statusText = "\(latest.teamShort) need \(need) run\(need == 1 ? "" : "s") from \(left) ball\(left == 1 ? "" : "s")"
        }
        return m
    }

    static func scorecard(_ match: CricketMatch, balls: [Ball]) -> Scorecard {
        guard let latest = balls.last else { return emptyScorecard(match) }
        let sameInnings = balls.filter { $0.inningsNumber == latest.inningsNumber }
        let atCrease = match.status == .live || match.status == .rainDelay

        var batters: [Batter] = []
        if atCrease {
            let out: Bool = if case .wicket = latest.outcome { true } else { false }
            let crossed = latest.runsRun % 2 == 1
            let overEnded = latest.isLegal && latest.legalBalls > 0 && latest.legalBalls % 6 == 0
            let facerKeepsStrike = crossed == overEnded
            if let f = latest.batter, !out {
                batters.append(Batter(name: f.name, runs: f.runs, balls: f.balls, fours: f.fours, sixes: f.sixes, isStriker: facerKeepsStrike))
            }
            if let o = latest.otherBatter {
                batters.append(Batter(name: o.name, runs: o.runs, balls: o.balls, fours: o.fours, sixes: o.sixes, isStriker: !out && !facerKeepsStrike))
            }
            batters.sort { $0.isStriker && !$1.isStriker }
        }

        let hasTarget = latest.target != nil && latest.ballLimit != nil && atCrease
        let lastWicket = sameInnings.last { if case .wicket = $0.outcome { true } else { false } }.map { shortenDismissal($0.dismissal) }

        return Scorecard(
            match: match,
            batters: batters,
            bowler: atCrease ? latest.bowler.map { Bowler(name: $0.name, legalBalls: $0.balls, maidens: $0.maidens, runs: $0.runs, wickets: $0.wickets) } : nil,
            recentBalls: sameInnings.suffix(12).map { Delivery(id: $0.id, outcome: $0.outcome, over: $0.over) },
            partnership: nil,
            lastWicket: lastWicket,
            currentRunRate: latest.runRate,
            requiredRunRate: hasTarget ? latest.requiredRate : nil,
            target: latest.target ?? match.target,
            runsRequired: hasTarget ? latest.remainingRuns : nil,
            ballsRemaining: hasTarget ? latest.remainingBalls : nil
        )
    }

    static func emptyScorecard(_ match: CricketMatch) -> Scorecard {
        Scorecard(match: match, batters: [], bowler: nil, recentBalls: [], partnership: nil, lastWicket: nil,
                  currentRunRate: nil, requiredRunRate: nil, target: match.target, runsRequired: nil, ballsRemaining: nil)
    }

    /// "JD Campbell c Prasidh Krishna b Kuldeep Yadav 62 (88m 60b 6x4 3x6) SR: 103.33" → "… 62 (60)"
    static func shortenDismissal(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"^(.*?\d+)\s*\((?:\d+m\s*)?(\d+)b"#),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let head = Range(m.range(at: 1), in: text), let balls = Range(m.range(at: 2), in: text) else {
            return text.components(separatedBy: " (").first ?? text
        }
        return "\(text[head]) (\(text[balls]))"
    }
}

// MARK: - Helpers

/// ESPN text contains HTML entities (e.g. "c &dagger;Cloete" marks the keeper).
func decodeEntities(_ s: String) -> String {
    guard s.contains("&") else { return s }
    let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "dagger": "†", "Dagger": "‡",
                 "ndash": "–", "mdash": "—", "rsquo": "’", "lsquo": "‘"]
    var out = ""
    var rest = Substring(s)
    while let amp = rest.firstIndex(of: "&") {
        out += rest[..<amp]
        let after = rest[amp...]
        if let semi = after.firstIndex(of: ";"), after.distance(from: after.startIndex, to: semi) <= 10 {
            let entity = after[after.index(after: after.startIndex)..<semi]
            var replacement: String?
            if entity.hasPrefix("#x"), let code = UInt32(entity.dropFirst(2), radix: 16), let scalar = Unicode.Scalar(code) {
                replacement = String(Character(scalar))
            } else if entity.hasPrefix("#"), let code = UInt32(entity.dropFirst()), let scalar = Unicode.Scalar(code) {
                replacement = String(Character(scalar))
            } else {
                replacement = named[String(entity)]
            }
            if let replacement {
                out += replacement
                rest = after[after.index(after: semi)...]
                continue
            }
        }
        out += "&"
        rest = after.dropFirst()
    }
    return out + rest
}

private extension Dictionary where Key == String, Value == Any {
    func dict(_ key: String) -> [String: Any]? { self[key] as? [String: Any] }
    func arr(_ key: String) -> [[String: Any]] { self[key] as? [[String: Any]] ?? [] }
    func string(_ key: String) -> String? {
        switch self[key] {
        case let s as String: s
        case let n as NSNumber: n.stringValue
        default: nil
        }
    }
    func int(_ key: String) -> Int? {
        switch self[key] {
        case let n as NSNumber: n.doubleValue.isFinite ? Int(n.doubleValue) : nil
        case let s as String: Int(s) ?? Double(s).flatMap { $0.isFinite ? Int($0) : nil }
        default: nil
        }
    }
    func double(_ key: String) -> Double? {
        switch self[key] {
        case let n as NSNumber: n.doubleValue.isFinite ? n.doubleValue : nil
        case let s as String: Double(s).flatMap { $0.isFinite ? $0 : nil }
        default: nil
        }
    }
    func bool(_ key: String) -> Bool? {
        switch self[key] {
        case let b as Bool: b
        case let n as NSNumber: n.boolValue
        case let s as String: s == "true" || s == "1"
        default: nil
        }
    }
}
