import AppKit
import Observation
import SwiftUI

/// Owns the single floating panel: positioning (notch-aware), sizing to its
/// SwiftUI content, showing/hiding, click-outside-to-collapse, and dragging.
@MainActor
final class OverlayController {
    private let panel = FloatingPanel()
    private let viewModel: ScoreViewModel
    private let settings: AppSettings
    private let layout = OverlayLayout()

    private var contentSize = CGSize(width: 320, height: 34)
    private var shrinkWork: DispatchWorkItem?
    private var clickMonitors: [Any] = []
    private var dragStart: (mouse: NSPoint, origin: NSPoint)?
    private var screenObserver: NSObjectProtocol?

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    init(viewModel: ScoreViewModel, settings: AppSettings, actions: AppActions) {
        self.viewModel = viewModel
        self.settings = settings

        let root = ScoreOverlay(
            viewModel: viewModel,
            layout: layout,
            actions: actions,
            onContentSize: { [weak self] size in self?.contentSizeChanged(size) },
            onDrag: { [weak self] phase in self?.handleDrag(phase) }
        )
        let hosting = FirstMouseHostingView(rootView: root)
        hosting.sizingOptions = []
        panel.contentView = hosting

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateLayout() }
        }

        observeContinuously { [weak self] in self?.updateLayout() }
        // Keep the widget out of screen shares and recordings (Zoom, Meet, QuickTime…).
        observeContinuously { [weak self] in
            guard let self else { return }
            self.panel.sharingType = self.settings.hideFromScreenSharing ? .none : .readOnly
        }
        observeContinuously { [weak self] in self?.updateVisibility() }
        observeContinuously { [weak self] in self?.updateClickMonitors() }
    }

    // MARK: Layout

    private func updateLayout() {
        guard let screen = ScreenGeometry.targetScreen() else { return }
        let dragged = settings.allowDragging && settings.customAnchor != nil

        var style = OverlayLayout.Style.floating
        if settings.position == .topCenter, !dragged, let notch = ScreenGeometry.notchRect(on: screen) {
            style = .notch(width: notch.width, height: notch.height)
        }
        let alignment: Alignment = (settings.position == .topRight && !dragged) ? .topTrailing : .top
        let draggable = settings.allowDragging && style == .floating

        if layout.style != style { layout.style = style }
        if layout.alignment != alignment { layout.alignment = alignment }
        if layout.isDraggable != draggable { layout.isDraggable = draggable }
        applyFrame(size: panel.frame.size)
    }

    private func frame(for size: CGSize) -> NSRect? {
        guard let screen = ScreenGeometry.targetScreen() else { return nil }
        let bounds = screen.frame
        let gap: CGFloat = 6
        let top = bounds.maxY - ScreenGeometry.menuBarHeight(on: screen) - gap
        var origin: NSPoint

        if settings.allowDragging, let anchor = settings.customAnchor {
            origin = NSPoint(x: anchor.x - size.width / 2, y: anchor.y - size.height)
        } else {
            switch (settings.position, layout.style) {
            case (.topCenter, .notch):
                let notch = ScreenGeometry.notchRect(on: screen) ?? bounds
                origin = NSPoint(x: notch.midX - size.width / 2, y: bounds.maxY - size.height)
            case (.topRight, _):
                origin = NSPoint(x: bounds.maxX - size.width - 10, y: top - size.height)
            default:
                origin = NSPoint(x: bounds.midX - size.width / 2, y: top - size.height)
            }
        }

        // Keep the widget fully on screen.
        origin.x = min(max(origin.x, bounds.minX), bounds.maxX - size.width)
        origin.y = min(max(origin.y, bounds.minY), bounds.maxY - size.height)
        return NSRect(origin: origin, size: size).integral
    }

    private func applyFrame(size: CGSize) {
        guard let rect = frame(for: size) else { return }
        if panel.frame != rect { panel.setFrame(rect, display: true) }
        panel.invalidateShadow()
    }

    /// The window tracks the SwiftUI content size. Growing happens immediately; shrinking
    /// waits for the collapse animation so it isn't clipped. The panel is never larger than
    /// the widget for more than that moment, so it doesn't block clicks on apps beneath.
    private func contentSizeChanged(_ size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }
        contentSize = size
        shrinkWork?.cancel()

        let current = panel.frame.size
        let union = CGSize(width: max(current.width, size.width), height: max(current.height, size.height))
        applyFrame(size: union)

        if union != size {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.applyFrame(size: self.contentSize)
            }
            shrinkWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.2 : 0.45), execute: work)
        } else {
            // Refresh the shadow once the expand animation has settled.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in self?.panel.invalidateShadow() }
        }
    }

    // MARK: Visibility

    private func updateVisibility() {
        let show = viewModel.shouldShowOverlay
        viewModel.setBackgroundMode(!show)

        if show {
            if !panel.isVisible {
                applyFrame(size: panel.frame.size)
                panel.alphaValue = 0
                panel.orderFrontRegardless()
            }
            guard panel.alphaValue < 1 else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = reduceMotion ? 0 : 0.25
                panel.animator().alphaValue = 1
            }
        } else if !show, panel.isVisible {
            if viewModel.isExpanded { viewModel.isExpanded = false }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = reduceMotion ? 0 : 0.2
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                Task { @MainActor in
                    guard let self, !self.viewModel.shouldShowOverlay else { return }
                    self.panel.orderOut(nil)
                }
            })
        }
    }

    // MARK: Click outside to collapse

    private func updateClickMonitors() {
        let expanded = viewModel.isExpanded
        if expanded, clickMonitors.isEmpty {
            if let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { [weak self] _ in
                Task { @MainActor in self?.collapse() }
            }) {
                clickMonitors.append(global)
            }
            if let local = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] event in
                if event.window !== self?.panel {
                    Task { @MainActor in self?.collapse() }
                }
                return event
            }) {
                clickMonitors.append(local)
            }
        } else if !expanded, !clickMonitors.isEmpty {
            clickMonitors.forEach(NSEvent.removeMonitor)
            clickMonitors.removeAll()
        }
    }

    private func collapse() {
        guard viewModel.isExpanded else { return }
        withAnimation(OverlayAnimation.expand(reduceMotion: reduceMotion)) {
            viewModel.isExpanded = false
        }
    }

    // MARK: Dragging (only when "Allow moving the widget" is on)

    private func handleDrag(_ phase: DragPhase) {
        guard layout.isDraggable else { return }
        let mouse = NSEvent.mouseLocation
        switch phase {
        case .changed:
            if dragStart == nil { dragStart = (mouse, panel.frame.origin) }
            guard let start = dragStart else { return }
            var origin = NSPoint(x: start.origin.x + mouse.x - start.mouse.x, y: start.origin.y + mouse.y - start.mouse.y)
            if let bounds = ScreenGeometry.targetScreen()?.frame {
                origin.x = min(max(origin.x, bounds.minX), bounds.maxX - panel.frame.width)
                origin.y = min(max(origin.y, bounds.minY), bounds.maxY - panel.frame.height)
            }
            panel.setFrameOrigin(origin)
        case .ended:
            dragStart = nil
            settings.customAnchor = CGPoint(x: panel.frame.midX, y: panel.frame.maxY)
        }
    }
}

enum DragPhase {
    case changed, ended
}

enum OverlayAnimation {
    static func expand(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.18) : .spring(response: 0.42, dampingFraction: 0.84)
    }
}

/// Re-runs `apply` whenever an observable property it reads changes.
@MainActor
func observeContinuously(_ apply: @escaping @MainActor () -> Void) {
    withObservationTracking {
        apply()
    } onChange: {
        Task { @MainActor in observeContinuously(apply) }
    }
}
