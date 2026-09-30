import SwiftUI

/// Horizontal chips for switching between simultaneous matches (expanded widget).
struct MatchSelectorView: View {
    let matches: [CricketMatch]
    let selectedID: String?
    let onSelect: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(matches) { match in
                    let selected = match.id == selectedID
                    Button { onSelect(match.id) } label: {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(dotColor(match.status))
                                .frame(width: 5, height: 5)
                            Text("\(match.teamA.shortName) v \(match.teamB.shortName)")
                                .font(Theme.label(10.5, selected ? .semibold : .medium))
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(selected ? AnyShapeStyle(.primary.opacity(0.14)) : AnyShapeStyle(.primary.opacity(0.05)), in: Capsule())
                        .overlay(Capsule().strokeBorder(.primary.opacity(selected ? 0.18 : 0), lineWidth: 0.5))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selected ? .primary : .secondary)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .scrollClipDisabled()
    }

    private func dotColor(_ status: MatchStatus) -> Color {
        switch status {
        case .live: Theme.live
        case .inningsBreak: Theme.pause
        case .rainDelay: Theme.rain
        case .completed: Theme.success
        case .upcoming, .abandoned: .secondary.opacity(0.6)
        }
    }
}

/// One row of the menu-bar match list.
struct MatchRow: View {
    let match: CricketMatch
    let isSelected: Bool
    var isFavorite = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .opacity(isSelected ? 1 : 0)
                .frame(width: 10)
            Text(match.shortTitle).font(Theme.label(12.5, isSelected ? .semibold : .regular))
            if isFavorite {
                Image(systemName: "star.fill").font(.system(size: 8)).foregroundStyle(.yellow)
            }
            Spacer(minLength: 8)
            Text(trailing)
                .font(Theme.score(11.5, .regular))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var trailing: String {
        switch match.status {
        case .upcoming:
            return match.startDate.map(Format.startTime) ?? "Upcoming"
        case .completed, .abandoned:
            return Format.shortResult(match.result ?? match.statusText, match: match)
        default:
            guard let inn = match.currentInnings else { return "Live" }
            return "\(inn.scoreText) (\(inn.oversText))"
        }
    }
}
