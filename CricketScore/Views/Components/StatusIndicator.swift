import SwiftUI

/// "● LIVE", "⏸ BREAK", "RAIN", "UPCOMING", "✓ ENDED".
struct StatusIndicator: View {
    let status: MatchStatus
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            icon
            if !compact {
                Text(title)
                    .font(.system(size: 9.5, weight: .bold).width(.expanded))
                    .foregroundStyle(color)
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle)
    }

    @ViewBuilder private var icon: some View {
        switch status {
        case .live:
            Circle()
                .fill(Theme.live)
                .frame(width: 7, height: 7)
                .shadow(color: Theme.live.opacity(0.7), radius: 3)
        default:
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
        }
    }

    private var title: String {
        switch status {
        case .live: "LIVE"
        case .inningsBreak: "BREAK"
        case .rainDelay: "RAIN"
        case .upcoming: "UPCOMING"
        case .completed: "ENDED"
        case .abandoned: "NO RESULT"
        }
    }

    private var accessibilityTitle: String {
        switch status {
        case .live: "Live"
        case .inningsBreak: "Innings break"
        case .rainDelay: "Rain delay"
        case .upcoming: "Upcoming"
        case .completed: "Match ended"
        case .abandoned: "No result"
        }
    }

    private var symbol: String {
        switch status {
        case .live: "circle.fill"
        case .inningsBreak: "pause.circle.fill"
        case .rainDelay: "cloud.rain.fill"
        case .upcoming: "clock.fill"
        case .completed: "checkmark.circle.fill"
        case .abandoned: "xmark.circle.fill"
        }
    }

    private var color: Color {
        switch status {
        case .live: Theme.live
        case .inningsBreak: Theme.pause
        case .rainDelay: Theme.rain
        case .upcoming: .secondary
        case .completed: Theme.success
        case .abandoned: .secondary
        }
    }
}

/// Brief "FOUR" / "SIX" / "WICKET" flash.
struct EventChip: View {
    let kind: ScoreHighlight.Kind
    var compact = false

    var body: some View {
        Text(compact ? shortTitle : title)
            .font(.system(size: compact ? 10 : 9.5, weight: .heavy).width(.expanded))
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 5 : 6)
            .frame(height: 16)
            .background(color, in: Capsule())
            .shadow(color: color.opacity(0.6), radius: 5)
            .fixedSize()
            .accessibilityLabel(title.capitalized)
    }

    private var title: String {
        switch kind {
        case .four: "FOUR"
        case .six: "SIX"
        case .wicket: "WICKET"
        }
    }

    private var shortTitle: String {
        switch kind {
        case .four: "4"
        case .six: "6"
        case .wicket: "W"
        }
    }

    var color: Color { Self.color(for: kind) }

    static func color(for kind: ScoreHighlight.Kind) -> Color {
        switch kind {
        case .four: Theme.four
        case .six: Theme.six
        case .wicket: Theme.wicket
        }
    }
}

struct TeamBadge: View {
    let team: Team
    var size: CGFloat = 22

    var body: some View {
        Text(team.shortName)
            .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(width: size, height: size)
            .background(TeamPalette.color(for: team).gradient, in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}
