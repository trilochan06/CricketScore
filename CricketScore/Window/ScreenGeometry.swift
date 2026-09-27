import AppKit

enum ScreenGeometry {
    /// The display that shows the menu bar (and, on MacBooks, the built-in notch).
    static func targetScreen() -> NSScreen? {
        NSScreen.screens.first
    }

    /// The camera housing in global screen coordinates, or `nil` on displays without a notch.
    static func notchRect(on screen: NSScreen) -> NSRect? {
        guard screen.safeAreaInsets.top > 0,
              var left = screen.auxiliaryTopLeftArea,
              var right = screen.auxiliaryTopRightArea else { return nil }
        let frame = screen.frame
        // The auxiliary areas are documented in the screen's space; normalise to global
        // coordinates so secondary-display origins are handled too.
        if !frame.intersects(left) {
            left = left.offsetBy(dx: frame.minX, dy: frame.minY)
            right = right.offsetBy(dx: frame.minX, dy: frame.minY)
        }
        let height = screen.safeAreaInsets.top
        let width = right.minX - left.maxX
        guard width > 40 else { return nil }
        return NSRect(x: left.maxX, y: frame.maxY - height, width: width, height: height)
    }

    /// Height of the menu bar on this screen (even when auto-hidden).
    static func menuBarHeight(on screen: NSScreen) -> CGFloat {
        let reserved = screen.frame.maxY - screen.visibleFrame.maxY
        return max(reserved, screen.safeAreaInsets.top, 24)
    }
}
