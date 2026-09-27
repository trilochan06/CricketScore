import SwiftUI

struct RecentBallsView: View {
    let deliveries: [Delivery]
    var highlightID: String?
    var maxCount = 10

    var body: some View {
        let shown = Array(deliveries.suffix(maxCount))
        HStack(spacing: 4) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, delivery in
                if index > 0, let over = delivery.over, let previous = shown[index - 1].over, over != previous {
                    Capsule()
                        .fill(.quaternary)
                        .frame(width: 1, height: 14)
                        .padding(.horizontal, 2)
                }
                BallView(delivery: delivery, isHighlighted: delivery.id == highlightID)
                    .transition(.asymmetric(insertion: .scale(scale: 0.4).combined(with: .opacity), removal: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: shown.map(\.id))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recent balls: " + shown.map(\.accessibilityLabel).joined(separator: ", "))
    }
}

struct BallView: View {
    let delivery: Delivery
    var isHighlighted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState private var pulse = false

    var body: some View {
        Text(delivery.label)
            .font(.system(size: delivery.category == .extra ? 8.5 : 11, weight: .bold, design: .rounded))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: 22, height: 22)
            .background(background, in: Circle())
            .overlay {
                if delivery.category == .dot {
                    Circle().strokeBorder(.tertiary, lineWidth: 1)
                }
            }
            .scaleEffect(pulse ? 1.22 : 1)
            .shadow(color: isHighlighted ? glow : .clear, radius: pulse ? 6 : 0)
            .onAppear { if isHighlighted { runPulse() } }
            .onChange(of: isHighlighted) { _, highlighted in if highlighted { runPulse() } }
    }

    private func runPulse() {
        guard !reduceMotion else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { pulse = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { pulse = false }
        }
    }

    private var glow: Color {
        switch delivery.category {
        case .four: Theme.four
        case .six: Theme.six
        case .wicket: Theme.wicket
        default: .clear
        }
    }

    private var foreground: AnyShapeStyle {
        switch delivery.category {
        case .four, .six, .wicket: AnyShapeStyle(.white)
        case .extra: AnyShapeStyle(Theme.extra)
        case .dot: AnyShapeStyle(.secondary)
        case .runs: AnyShapeStyle(.primary)
        }
    }

    private var background: AnyShapeStyle {
        switch delivery.category {
        case .four: AnyShapeStyle(Theme.four.gradient)
        case .six: AnyShapeStyle(Theme.six.gradient)
        case .wicket: AnyShapeStyle(Theme.wicket.gradient)
        case .extra: AnyShapeStyle(Theme.extra.opacity(0.16))
        case .runs: AnyShapeStyle(.primary.opacity(runsOpacity))
        case .dot: AnyShapeStyle(.clear)
        }
    }

    /// Singles are the lightest; twos and threes a touch stronger.
    private var runsOpacity: Double {
        if case .runs(let n) = delivery.outcome { return n >= 3 ? 0.2 : n == 2 ? 0.14 : 0.08 }
        return 0.08
    }
}
