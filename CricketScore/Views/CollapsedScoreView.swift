import SwiftUI

/// The glanceable, single-line state.
struct CollapsedScoreView: View {
    let viewModel: ScoreViewModel
    let layout: OverlayLayout

    var body: some View {
        if layout.isNotch {
            NotchWingsLayout(gap: layout.notchWidth + 14) {
                leftWing
                rightWing
            }
            .frame(height: max(layout.notchHeight, 28))
            .padding(.horizontal, WidgetShape.shoulder + 10)
        } else {
            floating
                .padding(.leading, 13)
                .padding(.trailing, 11)
                .frame(height: 34)
        }
    }

    // MARK: Floating pill

    private var floating: some View {
        HStack(spacing: 8) {
            switch viewModel.display {
            case .loading:
                ProgressView().controlSize(.mini)
                Text("Loading scores").font(Theme.label(12, .medium)).foregroundStyle(.secondary)
            case .unavailable(let message):
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(Theme.extra)
                Text("Scores unavailable").font(Theme.label(12, .medium))
                    .help(message)
            case .noLiveMatches(let next):
                Image(systemName: "cricket.ball").font(.system(size: 11)).foregroundStyle(.secondary)
                Text("No live matches").font(Theme.label(12, .medium))
                if let next, let start = next.startDate {
                    Text("Next \(next.shortTitle) · \(Format.startTime(start))")
                        .font(Theme.label(11.5)).foregroundStyle(.secondary)
                }
            case .match(let match, _):
                indicator(for: match, compact: false)
                matchSummary(match)
            }
            connectionIcon
            Image(systemName: "chevron.down")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(.tertiary)
        }
        .fixedSize()
    }

    @ViewBuilder
    private func matchSummary(_ match: CricketMatch) -> some View {
        switch match.status {
        case .live, .rainDelay, .inningsBreak:
            if let current = match.currentInnings {
                ScoreText(innings: current, showOvers: match.status != .inningsBreak)
                if let other = match.otherTeam {
                    Text("·").foregroundStyle(.tertiary)
                    if let otherInnings = match.innings.dropLast().last(where: { $0.team == other }) {
                        HStack(spacing: 3) {
                            Text(other.shortName).fontWeight(.medium)
                            Text(otherInnings.scoreText)
                        }
                        .font(Theme.score(12, .regular))
                        .foregroundStyle(.secondary)
                    } else if match.status == .inningsBreak, let target = match.target {
                        Text("\(other.shortName) need \(target)").font(Theme.score(12, .regular)).foregroundStyle(.secondary)
                    } else {
                        Text("vs \(other.shortName)").font(Theme.label(12)).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text(match.shortTitle).font(Theme.label(12, .semibold))
            }
        case .upcoming:
            Text(match.shortTitle).font(Theme.label(12, .semibold))
            if let start = match.startDate {
                TimelineView(.everyMinute) { context in
                    Text(Format.countdown(to: start, now: context.date))
                        .font(Theme.label(11.5)).foregroundStyle(.secondary).monospacedDigit()
                }
            }
        case .completed, .abandoned:
            Text(Format.shortResult(match.result ?? match.statusText, match: match))
                .font(Theme.label(12, .semibold))
                .lineLimit(1)
        }
    }

    // MARK: Notch wings

    @ViewBuilder private var leftWing: some View {
        HStack(spacing: 6) {
            switch viewModel.display {
            case .loading:
                ProgressView().controlSize(.mini)
            case .unavailable:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.extra)
                Text("Offline").foregroundStyle(.secondary)
            case .noLiveMatches:
                Image(systemName: "cricket.ball").foregroundStyle(.secondary)
                Text("No live").foregroundStyle(.secondary)
            case .match(let match, _):
                indicator(for: match, compact: true)
                switch match.status {
                case .upcoming:
                    Text(match.teamA.shortName).fontWeight(.semibold)
                case .completed, .abandoned:
                    Text(match.result.flatMap { r in match.teams.first { r.hasPrefix($0.name) }?.shortName } ?? "FT")
                        .fontWeight(.semibold)
                default:
                    if let current = match.currentInnings {
                        ScoreText(innings: current, showOvers: false)
                    } else {
                        Text(match.teamA.shortName).fontWeight(.semibold)
                    }
                }
            }
        }
        .font(Theme.score(12.5))
        .foregroundStyle(.white)
        .fixedSize()
    }

    @ViewBuilder private var rightWing: some View {
        HStack(spacing: 5) {
            connectionIcon
            switch viewModel.display {
            case .loading:
                Text("…").foregroundStyle(.secondary)
            case .unavailable:
                Text("Retry").foregroundStyle(.secondary)
            case .noLiveMatches(let next):
                if let start = next?.startDate {
                    Text(start.formatted(date: .omitted, time: .shortened)).foregroundStyle(.secondary)
                } else {
                    Text("—").foregroundStyle(.tertiary)
                }
            case .match(let match, _):
                switch match.status {
                case .upcoming:
                    Text("v \(match.teamB.shortName)").fontWeight(.semibold)
                    if let start = match.startDate {
                        TimelineView(.everyMinute) { context in
                            Text(Format.compactCountdown(to: start, now: context.date)).foregroundStyle(.secondary)
                        }
                    }
                case .completed, .abandoned:
                    Text("won").foregroundStyle(.secondary)
                case .inningsBreak:
                    Text("Break").foregroundStyle(Theme.pause)
                default:
                    if let current = match.currentInnings {
                        Text(current.oversText).numericTransition(current.legalBalls)
                        Text("ov").foregroundStyle(.secondary).font(Theme.label(10))
                    }
                }
            }
        }
        .font(Theme.score(12.5))
        .foregroundStyle(.white)
        .fixedSize()
    }

    // MARK: Shared pieces

    @ViewBuilder
    private func indicator(for match: CricketMatch, compact: Bool) -> some View {
        ZStack {
            if let highlight = viewModel.highlight, match.status == .live {
                EventChip(kind: highlight.kind, compact: compact)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            } else {
                StatusIndicator(status: match.status, compact: compact)
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.highlight)
    }

    @ViewBuilder private var connectionIcon: some View {
        switch viewModel.connection {
        case .ok: EmptyView()
        case .offline:
            Image(systemName: "wifi.slash").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                .help("Offline — showing last available score")
        case .failing(let message):
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10)).foregroundStyle(Theme.extra)
                .help(message)
        }
    }
}

/// "IND 184/4 32.2" with rolling digits.
struct ScoreText: View {
    let innings: InningsScore
    var showOvers = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(innings.team.shortName).font(Theme.score(12.5, .medium))
            Text(innings.scoreText)
                .font(Theme.score(13, .bold))
                .numericTransition(innings.runs * 100 + innings.wickets)
            if showOvers {
                Text(innings.oversText)
                    .font(Theme.score(11, .regular))
                    .foregroundStyle(.secondary)
                    .numericTransition(innings.legalBalls)
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(innings.team.name) \(innings.runs) for \(innings.wickets), \(innings.oversText) overs")
    }
}
