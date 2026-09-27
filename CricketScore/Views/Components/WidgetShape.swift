import SwiftUI

/// Outline of the widget.
/// - Floating: a rounded rectangle (a capsule when collapsed).
/// - Notch: flat top flush with the screen edge, small concave "shoulders" that melt
///   into the menu bar, and rounded bottom corners — the camera housing appears to grow.
struct WidgetShape: Shape {
    var isNotch: Bool
    var cornerRadius: CGFloat
    static let shoulder: CGFloat = 8

    var animatableData: CGFloat {
        get { cornerRadius }
        set { cornerRadius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        guard isNotch else {
            let radius = min(cornerRadius, rect.height / 2)
            return Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
        }

        let s = Self.shoulder
        let r = min(cornerRadius, (rect.width - 2 * s) / 2, rect.height - s)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + s, y: rect.minY + s), control: CGPoint(x: rect.minX + s, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + s, y: rect.maxY - r))
        path.addQuadCurve(to: CGPoint(x: rect.minX + s + r, y: rect.maxY), control: CGPoint(x: rect.minX + s, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - s - r, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - s, y: rect.maxY - r), control: CGPoint(x: rect.maxX - s, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - s, y: rect.minY + s))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - s, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// Places two "wings" either side of a fixed gap (the notch), giving both wings the
/// same width so the whole widget stays centred on the camera.
struct NotchWingsLayout: Layout {
    var gap: CGFloat
    var minWingWidth: CGFloat = 64

    private func wingWidth(_ subviews: Subviews) -> CGFloat {
        let widths = subviews.map { $0.sizeThatFits(.unspecified).width }
        return max(widths.max() ?? 0, minWingWidth)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: wingWidth(subviews) * 2 + gap, height: max(height, proposal.height ?? 0))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let wing = wingWidth(subviews)
        let proposalSize = ProposedViewSize(width: wing, height: bounds.height)
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading, proposal: proposalSize)
        subviews[1].place(at: CGPoint(x: bounds.maxX, y: bounds.midY), anchor: .trailing, proposal: proposalSize)
    }
}
