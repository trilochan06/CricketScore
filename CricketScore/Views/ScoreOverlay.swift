import SwiftUI

/// Root view hosted in the floating panel. Reports the widget's size so the window
/// can hug it exactly, and forwards drags to the window controller.
struct ScoreOverlay: View {
    let viewModel: ScoreViewModel
    let layout: OverlayLayout
    let actions: AppActions
    let onContentSize: (CGSize) -> Void
    let onDrag: (DragPhase) -> Void

    @Environment(\.colorScheme) private var systemColorScheme

    var body: some View {
        ScoreOverlayWidget(viewModel: viewModel, layout: layout, actions: actions)
            .simultaneousGesture(dragGesture, including: layout.isDraggable && !viewModel.isExpanded ? .all : .subviews)
            .fixedSize()
            .onGeometryChange(for: CGSize.self) { $0.size } action: { onContentSize($0) }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: layout.alignment)
            // The notch style is always dark so it blends with the camera housing;
            // the floating style follows the app appearance setting.
            .environment(\.colorScheme, layout.isNotch ? .dark : systemColorScheme)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { _ in onDrag(.changed) }
            .onEnded { _ in onDrag(.ended) }
    }
}

/// The widget itself: morphs between collapsed and expanded inside one shape.
struct ScoreOverlayWidget: View {
    let viewModel: ScoreViewModel
    let layout: OverlayLayout
    let actions: AppActions

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isSnapshot) private var isSnapshot

    private var shape: WidgetShape {
        WidgetShape(isNotch: layout.isNotch, cornerRadius: viewModel.isExpanded ? 22 : (layout.isNotch ? 12 : 17))
    }

    var body: some View {
        let expanded = viewModel.isExpanded
        let isLive: Bool = if case .match(let m, _) = viewModel.display { m.status == .live } else { false }
        let highlightColor = isLive ? viewModel.highlight.map { EventChip.color(for: $0.kind) } : nil

        ZStack(alignment: .top) {
            if expanded {
                ExpandedScoreView(viewModel: viewModel, layout: layout, actions: actions, onClose: collapse)
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeOut(duration: 0.2).delay(0.08)),
                        removal: .opacity.animation(.easeIn(duration: 0.1))))
            } else {
                CollapsedScoreView(viewModel: viewModel, layout: layout)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: expand)
                    .transition(.asymmetric(
                        insertion: .opacity.animation(.easeOut(duration: 0.2).delay(0.1)),
                        removal: .opacity.animation(.easeIn(duration: 0.08))))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Shows the full scorecard")
            }
        }
        .background { background }
        .clipShape(shape)
        .overlay {
            shape.stroke(
                highlightColor?.opacity(0.9) ?? (layout.isNotch ? Color.white.opacity(0.06) : Color.primary.opacity(0.12)),
                lineWidth: highlightColor == nil ? 0.5 : 1.5)
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.highlight)
        .animation(OverlayAnimation.expand(reduceMotion: reduceMotion), value: expanded)
        .animation(OverlayAnimation.expand(reduceMotion: reduceMotion), value: layout.style)
    }

    @ViewBuilder private var background: some View {
        if layout.isNotch {
            Color.black
        } else if isSnapshot {
            Color(nsColor: .windowBackgroundColor).opacity(0.92)
        } else {
            ZStack {
                VisualEffectBackground(material: .hudWindow)
                Color(nsColor: .windowBackgroundColor).opacity(0.35)
            }
        }
    }

    private func expand() {
        withAnimation(OverlayAnimation.expand(reduceMotion: reduceMotion)) { viewModel.isExpanded = true }
    }

    private func collapse() {
        withAnimation(OverlayAnimation.expand(reduceMotion: reduceMotion)) { viewModel.isExpanded = false }
    }
}
