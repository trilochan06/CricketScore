import Observation
import SwiftUI

/// Geometry the SwiftUI overlay needs from the window controller.
@MainActor
@Observable
final class OverlayLayout {
    enum Style: Equatable {
        /// Grows out of the MacBook camera housing. Always black, flush with the top edge.
        case notch(width: CGFloat, height: CGFloat)
        /// A free-floating blurred pill below the menu bar.
        case floating
    }

    var style: Style = .floating
    /// How content sits inside the window while the window is briefly larger than it (during collapse).
    var alignment: Alignment = .top
    var isDraggable = false

    var isNotch: Bool {
        if case .notch = style { return true }
        return false
    }

    var notchWidth: CGFloat {
        if case .notch(let width, _) = style { return width }
        return 0
    }

    var notchHeight: CGFloat {
        if case .notch(_, let height) = style { return height }
        return 0
    }
}
