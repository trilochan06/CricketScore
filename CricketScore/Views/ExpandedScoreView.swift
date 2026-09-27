import SwiftUI

/// The detailed state. Information is layered: headline score and situation first,
/// then players and recent balls, with venue/toss/etc. behind a "Match info" disclosure.
struct ExpandedScoreView: View {
    let viewModel: ScoreViewModel
    let layout: OverlayLayout
    let actions: AppActions
    let onClose: () -> Void

    @ViewState private var showInfo = false

    static let floatingWidth: CGFloat = 348

    private var width: CGFloat {
        layout.isNotch ? max(Self.floatingWidth + 2 * WidgetShape.shoulder, layout.notchWidth + 230) : Self.floatingWidth
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 12) {
                ConnectionBanner(connection: viewModel.connection, lastUpdated: viewModel.lastUpdated, onRetry: viewModel.refresh)
                    .reveal(0)
                if viewModel.matches.count > 1 {
                    MatchSelectorView(matches: viewModel.matches, selectedID: viewModel.selectedMatchID, onSelect: viewModel.select)
                        .reveal(1)
                }
                content
                footer.reveal(6)
            }
            .padding(.horizontal, 16 + (layout.isNotch ? WidgetShape.shoulder : 0))
            .padding(.top, layout.isNotch ? 6 : 2)
            .padding(.bottom, 12)
        }
        .frame(width: width)
    }

    // MARK: Header

    @ViewBuilder private var header: some View {
        if layout.isNotch {
            NotchWingsLayout(gap: layout.notchWidth + 14) {
                headerStatus
                headerButtons
            }
            .frame(height: max(layout.notchHeight, 28))
            .padding(.horizontal, WidgetShape.shoulder + 12)
        } else {
            HStack {
                headerStatus
                Spacer()
                headerButtons
            }
            .padding(.horizontal, 14)
            .frame(height: 36)
        }
    }

    @ViewBuilder private var headerStatus: some View {
        if case .match(let match, _) = viewModel.display {
            ZStack(alignment: .leading) {
                if let highlight = viewModel.highlight, match.status == .live {
                    EventChip(kind: highlight.kind).transition(.scale(scale: 0.6).combined(with: .opacity))
                } else {
                    StatusIndicator(status: match.status).transition(.opacity)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.highlight)
        } else {
            HStack(spacing: 5) {
                Image(systemName: "cricket.ball.fill").font(.system(size: 10))
                Text("CRICKET").font(.system(size: 9.5, weight: .bold).width(.expanded))
            }
            .foregroundStyle(.secondary)
        }
    }

    private var headerButtons: some View {
        HStack(spacing: 2) {
            Menu {
                if viewModel.matches.count > 1 {
                    Section("Matches") {
                        ForEach(viewModel.matches) { match in
                            Button {
                                viewModel.select(match.id)
                            } label: {
                                if match.id == viewModel.selectedMatchID {
                                    Label(match.shortTitle, systemImage: "checkmark")
                                } else {
                                    Text(match.shortTitle)
                                }
                            }
                        }
                    }
                }
                Button("Refresh Now", action: viewModel.refresh)
                Button("Pause Overlay", action: viewModel.pauseOverlay)
                Divider()
                Button("Settings…", action: actions.openSettings)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Circle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More")

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 20, height: 20)
                    .background(.primary.opacity(0.08), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Collapse")
        }
        .foregroundStyle(.secondary)
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        switch viewModel.display {
        case .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading live scores…").font(Theme.label(12)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 60)

        case .unavailable(let message):
            MessageView(symbol: "exclamationmark.triangle", title: "Unable to load scores", detail: message,
                        buttonTitle: "Retry", action: viewModel.refresh)

        case .noLiveMatches(let next):
            VStack(spacing: 12) {
                MessageView(symbol: "cricket.ball", title: "No live cricket matches",
                            detail: "We'll automatically check again.")
                if let next { NextMatchCard(match: next) }
            }
            .reveal(2)

        case .match(let match, let card):
            matchContent(match, card)
        }
    }

    @ViewBuilder
    private func matchContent(_ match: CricketMatch, _ card: Scorecard?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(match.fullTitle).font(Theme.label(14, .semibold)).lineLimit(1)
            if !match.subtitle.isEmpty {
                Text(match.subtitle).font(Theme.label(11)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .reveal(2)

        if match.status == .upcoming {
            UpcomingView(match: match).reveal(3)
        } else {
            Scoreboard(match: match).reveal(3)
            SituationView(match: match, card: card).reveal(4)

            if let card, match.status == .live || match.status == .rainDelay {
                if !card.batters.isEmpty || card.bowler != nil {
                    Divider().opacity(0.5)
                    PlayersTable(batters: card.batters, bowler: card.bowler, partnership: card.partnership)
                        .reveal(5)
                }
                if !card.recentBalls.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionLabel("RECENT BALLS")
                        RecentBallsView(deliveries: card.recentBalls, highlightID: viewModel.highlight?.deliveryID)
                    }
                    .reveal(5)
                }
            }
            if let card, match.status == .completed, !card.batters.isEmpty {
                Divider().opacity(0.5)
                PlayersTable(batters: card.batters, bowler: nil).reveal(5)
            }
        }

        MatchInfoDisclosure(match: match, card: card, isExpanded: $showInfo).reveal(5)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if viewModel.isUsingMockData {
                Text("DEMO DATA")
                    .font(.system(size: 8.5, weight: .bold).width(.expanded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .frame(height: 15)
                    .background(.primary.opacity(0.07), in: Capsule())
                    .help("Simulated scores. Switch to live data in Settings → Data.")
            }
            TimelineView(.periodic(from: .now, by: 5)) { context in
                Text(Format.updatedAgo(viewModel.lastUpdated, now: context.date))
                    .font(Theme.label(10.5))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            RefreshButton(isRefreshing: viewModel.isRefreshing, action: viewModel.refresh)
        }
    }
}

// MARK: - Pieces

private struct Scoreboard: View {
    let match: CricketMatch

    var body: some View {
        VStack(spacing: 7) {
            ForEach(match.teamsInBattingOrder, id: \.self) { team in
                row(team)
            }
        }
    }

    private func row(_ team: Team) -> some View {
        let innings = match.latestInnings(for: team)
        let batting = match.battingTeam == team
        let dimmed = match.status.isInProgress && !batting
        return HStack(spacing: 9) {
            TeamBadge(team: team)
            Text(team.name)
                .font(Theme.label(13, batting ? .semibold : .medium))
                .lineLimit(1)
            if batting {
                Image(systemName: "figure.cricket")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("batting")
            }
            Spacer(minLength: 8)
            if let innings {
                Text(innings.scoreText)
                    .font(Theme.score(batting ? 19 : 15, .bold))
                    .numericTransition(innings.runs * 100 + innings.wickets)
                Text("(\(innings.oversText))")
                    .font(Theme.score(11, .regular))
                    .foregroundStyle(.secondary)
                    .numericTransition(innings.legalBalls)
            } else {
                Text("Yet to bat").font(Theme.label(11)).foregroundStyle(.tertiary)
            }
        }
        .opacity(dimmed ? 0.72 : 1)
        .accessibilityElement(children: .combine)
    }
}

private struct SituationView: View {
    let match: CricketMatch
    let card: Scorecard?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            banner
            let chips = rateChips
            if !chips.isEmpty {
                HStack(spacing: 6) {
                    ForEach(chips, id: \.0) { title, value in
                        HStack(spacing: 4) {
                            Text(title).font(.system(size: 9, weight: .semibold).width(.expanded)).foregroundStyle(.tertiary)
                            Text(value).font(Theme.score(11, .semibold))
                        }
                        .padding(.horizontal, 7)
                        .frame(height: 20)
                        .background(.primary.opacity(0.06), in: Capsule())
                    }
                }
            }
        }
    }

    @ViewBuilder private var banner: some View {
        switch match.status {
        case .completed, .abandoned:
            Label {
                Text(match.result ?? match.statusText).font(Theme.label(12.5, .semibold))
            } icon: {
                Image(systemName: match.status == .completed ? "checkmark.seal.fill" : "xmark.seal.fill")
                    .foregroundStyle(match.status == .completed ? Theme.success : .secondary)
            }
        case .inningsBreak:
            Label {
                Text(match.statusText.isEmpty ? "Innings break" : match.statusText).font(Theme.label(12.5, .semibold))
            } icon: {
                Image(systemName: "pause.circle.fill").foregroundStyle(Theme.pause)
            }
        case .rainDelay:
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Rain delay").font(Theme.label(12.5, .semibold))
                    if !match.statusText.isEmpty {
                        Text(match.statusText).font(Theme.label(11)).foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: "cloud.rain.fill").foregroundStyle(Theme.rain)
            }
        default:
            if let need = card?.runsRequired, let balls = card?.ballsRemaining, let team = match.battingTeam {
                (Text("\(team.shortName) need ")
                    + Text("\(need)").fontWeight(.bold)
                    + Text(" run\(need == 1 ? "" : "s") from ")
                    + Text("\(balls)").fontWeight(.bold)
                    + Text(" ball\(balls == 1 ? "" : "s")"))
                    .font(Theme.label(12.5))
                    .monospacedDigit()
            } else if !match.statusText.isEmpty {
                Text(match.statusText).font(Theme.label(12)).foregroundStyle(.secondary)
            }
        }
    }

    private var rateChips: [(String, String)] {
        var chips: [(String, String)] = []
        guard match.status.isInProgress else { return chips }
        if let crr = Format.rate(card?.currentRunRate), match.status != .inningsBreak { chips.append(("CRR", crr)) }
        if let rrr = Format.rate(card?.requiredRunRate) { chips.append(("RRR", rrr)) }
        if let target = card?.target ?? match.target { chips.append(("TARGET", "\(target)")) }
        return chips
    }
}

private struct UpcomingView: View {
    let match: CricketMatch

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                TeamBadge(team: match.teamA, size: 30)
                Text("vs").font(Theme.label(11)).foregroundStyle(.tertiary)
                TeamBadge(team: match.teamB, size: 30)
                Spacer()
                if let start = match.startDate {
                    VStack(alignment: .trailing, spacing: 2) {
                        TimelineView(.everyMinute) { context in
                            Text(Format.countdown(to: start, now: context.date))
                                .font(Theme.score(14, .semibold))
                        }
                        Text(Format.startTime(start)).font(Theme.label(11)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct NextMatchCard: View {
    let match: CricketMatch

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("NEXT MATCH")
            HStack(spacing: 10) {
                TeamBadge(team: match.teamA)
                TeamBadge(team: match.teamB).padding(.leading, -7)
                VStack(alignment: .leading, spacing: 1) {
                    Text(match.fullTitle).font(Theme.label(12.5, .semibold)).lineLimit(1)
                    if let start = match.startDate {
                        Text("Starts \(Format.startTime(start))").font(Theme.label(11)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct MatchInfoDisclosure: View {
    let match: CricketMatch
    let card: Scorecard?
    @Binding var isExpanded: Bool

    var body: some View {
        let rows = infoRows
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        SectionLabel("MATCH INFO")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 7.5, weight: .bold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isExpanded {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(rows, id: \.1) { symbol, text in
                            Label {
                                Text(text).font(Theme.label(11.5)).foregroundStyle(.secondary).lineLimit(2)
                            } icon: {
                                Image(systemName: symbol).font(.system(size: 10)).foregroundStyle(.tertiary).frame(width: 14)
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private var infoRows: [(String, String)] {
        var rows: [(String, String)] = []
        rows.append(("sportscourt", "\(match.format.displayName)\(match.title.isEmpty || match.title == match.format.displayName ? "" : " · \(match.title)")"))
        if !match.series.isEmpty { rows.append(("trophy", match.series)) }
        if !match.venue.isEmpty { rows.append(("mappin.and.ellipse", match.venue)) }
        if let toss = match.toss, !toss.isEmpty { rows.append(("circle.lefthalf.filled", toss)) }
        if let start = match.startDate { rows.append(("calendar", start.formatted(date: .abbreviated, time: .shortened))) }
        if let last = card?.lastWicket, !last.isEmpty { rows.append(("xmark.circle", "Last wicket: \(last)")) }
        return rows
    }
}

struct ConnectionBanner: View {
    let connection: ConnectionState
    let lastUpdated: Date?
    let onRetry: () -> Void

    var body: some View {
        switch connection {
        case .ok:
            EmptyView()
        case .offline:
            banner(symbol: "wifi.slash", tint: .secondary, title: "Offline",
                   detail: lastUpdated == nil ? "Waiting for a connection" : "Showing last available score")
        case .failing(let message):
            banner(symbol: "exclamationmark.triangle.fill", tint: Theme.extra, title: "Unable to update score",
                   detail: lastUpdated == nil ? message : nil)
        }
    }

    private func banner(symbol: String, tint: Color, title: String, detail: String?) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Theme.label(12, .semibold))
                if let detail {
                    Text(detail).font(Theme.label(10.5)).foregroundStyle(.secondary).lineLimit(2)
                } else {
                    TimelineView(.periodic(from: .now, by: 5)) { context in
                        Text(Format.updatedAgo(lastUpdated, now: context.date).replacingOccurrences(of: "Updated", with: "Last updated"))
                            .font(Theme.label(10.5)).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 4)
            Button(action: onRetry) {
                Label("Retry", systemImage: "arrow.clockwise").font(Theme.label(11, .medium))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(.primary.opacity(0.08), in: Capsule())
        }
        .padding(10)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct MessageView: View {
    let symbol: String
    let title: String
    let detail: String
    var buttonTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 20, weight: .light)).foregroundStyle(.secondary)
            Text(title).font(Theme.label(13.5, .semibold))
            Text(detail).font(Theme.label(11.5)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let buttonTitle, let action {
                Button(buttonTitle, action: action).controlSize(.small).padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

struct RefreshButton: View {
    let isRefreshing: Bool
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 10.5, weight: .semibold))
                .rotationEffect(.degrees(isRefreshing && !reduceMotion ? 360 : 0))
                .animation(isRefreshing && !reduceMotion ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default,
                           value: isRefreshing)
                .frame(width: 22, height: 22)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("Refresh now")
        .accessibilityLabel("Refresh")
    }
}

/// Staggered fade/slide-in for sections when the widget expands.
private struct Reveal: ViewModifier {
    let index: Int
    @ViewState private var visible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible || reduceMotion ? 0 : -6)
            .onAppear {
                if reduceMotion {
                    visible = true
                } else {
                    withAnimation(.easeOut(duration: 0.28).delay(0.05 + Double(index) * 0.035)) { visible = true }
                }
            }
    }
}

extension View {
    func reveal(_ index: Int) -> some View { modifier(Reveal(index: index)) }
}
