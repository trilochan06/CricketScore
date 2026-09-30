import AppKit
import CoreMediaIO

/// Keeps the widget out of the way while you're focused:
/// - a full-screen app is in front (videos, presentations, full-screen work), or
/// - a camera is in use (video calls).
/// Checks only on app/Space switches plus a light 4-second timer — no permissions needed.
@MainActor
final class FocusMonitor {
    private let settings: AppSettings
    private let onChange: (Bool) -> Void
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    private(set) var isSuppressed = false

    init(settings: AppSettings, onChange: @escaping (Bool) -> Void) {
        self.settings = settings
        self.onChange = onChange
    }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // Give the Space transition a moment to settle before measuring windows.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { MainActor.assumeIsolated { self?.evaluate() } }
            })
        }
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
        timer?.tolerance = 1
        evaluate()
    }

    func evaluate() {
        let fullScreen = settings.hideInFullScreen && Self.frontmostAppIsFullScreen()
        let call = settings.hideDuringCalls && Self.cameraInUse()
        let suppressed = fullScreen || call
        guard suppressed != isSuppressed else { return }
        isSuppressed = suppressed
        onChange(suppressed)
    }

    /// True when the frontmost app (not us) has a window covering the whole main display.
    static func frontmostAppIsFullScreen() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let screen = ScreenGeometry.targetScreen() else { return false }
        let size = screen.frame.size
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for window in windows {
            guard (window[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let b = window[kCGWindowBounds as String] as? [String: Double] else { continue }
            // Global display coordinates: the main display starts at (0, 0).
            if (b["X"] ?? -1) == 0, (b["Y"] ?? -1) == 0, (b["Width"] ?? 0) >= size.width, (b["Height"] ?? 0) >= size.height {
                return true
            }
        }
        return false
    }

    /// True when any camera is streaming to any app (a video call, Photo Booth, …).
    static func cameraInUse() -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &size) == 0, size > 0 else {
            return false
        }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, size, &used, &devices) == 0 else {
            return false
        }
        for device in devices {
            var running = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
            var value: UInt32 = 0
            var valueSize = UInt32(MemoryLayout<UInt32>.size)
            if CMIOObjectGetPropertyData(device, &running, 0, nil, valueSize, &valueSize, &value) == 0, value != 0 {
                return true
            }
        }
        return false
    }
}
