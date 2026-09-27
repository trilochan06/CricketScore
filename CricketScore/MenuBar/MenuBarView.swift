import SwiftUI

/// Contents of the menu-bar extra window.
struct MenuBarView: View {
    let viewModel: ScoreViewModel
    let settings: AppSettings
    let updates: UpdateChecker
    let actions: AppActions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let match = viewModel.selectedMatch {
                SelectedMatchCard(match: match, card: viewModel.scorecard?.match.id == match.id ? viewModel.scorecard : nil,
                                  highlight: viewModel.highlight)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
            }
            if viewModel.connection != .ok {
                ConnectionBanner(connection: viewModel.connection, lastUpdated: viewModel.lastUpdated, onRetry: viewModel.refresh)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
            }

            if let release = updates.available {
                MenuRowButton(title: "Update available — v\(release.version)", symbol: "arrow.down.circle.fill", action: updates.openDownload)
                    .foregroundStyle(Color.accentColor)
            }
            MenuDivider()
            matchLists
            MenuDivider()

            MenuRowButton(title: overlayVisible ? "Pause Overlay" : "Show Overlay",
                          symbol: overlayVisible ? "pause.circle" : "play.circle") {
                if overlayVisible { viewModel.pauseOverlay() } else { viewModel.showOverlay() }
            }
            MenuRowButton(title: "Refresh Now", symbol: "arrow.clockwise", action: viewModel.refresh)
            MenuRowButton(title: "Settings…", symbol: "gearshape", shortcut: "⌘,", action: actions.openSettings)
                .keyboardShortcut(",", modifiers: .command)
            MenuDivider()
            MenuRowButton(title: "Quit Cricket Score", symbol: "power", shortcut: "⌘Q", action: actions.quit)
                .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.vertical, 6)
        .frame(width: 300)
        .onAppear(perform: viewModel.refreshIfStale)
    }

    private var overlayVisible: Bool { viewModel.shouldShowOverlay }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "cricket.ball.fill").foregroundStyle(Theme.live)
            Text("Cricket Scores").font(.system(size: 13, weight: .semibold))
            if viewModel.isUsingMockData {
                Text("DEMO")
                    .font(.system(size: 8.5, weight: .bold).width(.expanded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .frame(height: 15)
                    .background(.primary.opacity(0.07), in: Capsule())
            }
            Spacer()
            RefreshButton(isRefreshing: viewModel.isRefreshing, action: viewModel.refresh)
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    @ViewBuilder private var matchLists: some View {
        if viewModel.matches.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.hasLoaded ? "No live cricket matches" : "Loading…").font(.system(size: 12.5, weight: .medium))
                Text("We'll automatically check again.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        } else {
            section("Live Matches", viewModel.inProgressMatches)
            section("Upcoming", viewModel.upcomingMatches)
            section("Results", viewModel.finishedMatches)
        }
    }

    @ViewBuilder
    private func section(_ title: String, _ matches: [CricketMatch]) -> some View {
        if !matches.isEmpty {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 2)
            ForEach(matches) { match in
                MenuRowContainer(action: { viewModel.select(match.id) }) {
                    MatchRow(match: match, isSelected: match.id == viewModel.selectedMatchID)
                }
            }
        }
    }
}

private struct SelectedMatchCard: View {
    let match: CricketMatch
    let card: Scorecard?
    let highlight: ScoreHighlight?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let highlight, match.status == .live {
                    EventChip(kind: highlight.kind)
                } else {
                    StatusIndicator(status: match.status)
                }
                Spacer()
                Text(match.subtitle).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            ForEach(match.teamsInBattingOrder, id: \.self) { team in
                HStack(spacing: 8) {
                    TeamBadge(team: team, size: 18)
                    Text(team.name).font(.system(size: 12.5, weight: match.battingTeam == team ? .semibold : .regular))
                    Spacer()
                    if let inn = match.latestInnings(for: team) {
                        Text(inn.scoreText).font(Theme.score(14, .bold)).numericTransition(inn.runs * 100 + inn.wickets)
                        Text("(\(inn.oversText))").font(Theme.score(10.5, .regular)).foregroundStyle(.secondary)
                    } else if match.status == .upcoming, let start = match.startDate, team == match.teamB {
                        Text(Format.startTime(start)).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            }
            if !match.statusText.isEmpty {
                Text(match.statusText).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(10)
        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Native-feeling menu rows

struct MenuRowButton: View {
    let title: String
    let symbol: String
    var shortcut: String?
    let action: () -> Void

    var body: some View {
        MenuRowContainer(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol).frame(width: 16)
                Text(title)
                Spacer()
                if let shortcut { Text(shortcut).foregroundStyle(.secondary) }
            }
            .font(.system(size: 13))
        }
    }
}

struct MenuRowContainer<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            label()
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                .background(hovering ? Color.accentColor.opacity(0.85) : .clear,
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .foregroundStyle(hovering ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .onHover { hovering = $0 }
    }
}

private struct MenuDivider: View {
    var body: some View {
        Divider().padding(.horizontal, 14).padding(.vertical, 5)
    }
}
