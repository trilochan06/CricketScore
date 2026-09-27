import AppKit
import SwiftUI

enum Theme {
    static let live = Color(red: 1.0, green: 0.27, blue: 0.23)
    static let four = Color(red: 0.16, green: 0.55, blue: 1.0)
    static let six = Color(red: 0.64, green: 0.38, blue: 1.0)
    static let wicket = Color(red: 0.97, green: 0.27, blue: 0.25)
    static let extra = Color(red: 1.0, green: 0.62, blue: 0.1)
    static let success = Color(red: 0.2, green: 0.78, blue: 0.42)
    static let rain = Color(red: 0.36, green: 0.7, blue: 1.0)
    static let pause = Color(red: 1.0, green: 0.62, blue: 0.1)

    static func score(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }

    static func label(_ size: CGFloat = 11, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    /// Small-caps style section header.
    static let sectionHeader = Font.system(size: 9.5, weight: .semibold).width(.expanded)
}

enum TeamPalette {
    private static let known: [String: Color] = [
        "IND": Color(red: 0.13, green: 0.45, blue: 0.95),
        "AUS": Color(red: 0.98, green: 0.76, blue: 0.1),
        "ENG": Color(red: 0.2, green: 0.35, blue: 0.75),
        "SA": Color(red: 0.1, green: 0.62, blue: 0.4),
        "RSA": Color(red: 0.1, green: 0.62, blue: 0.4),
        "PAK": Color(red: 0.05, green: 0.55, blue: 0.3),
        "NZ": Color(red: 0.45, green: 0.47, blue: 0.5),
        "SL": Color(red: 0.2, green: 0.3, blue: 0.75),
        "BAN": Color(red: 0.0, green: 0.55, blue: 0.4),
        "WI": Color(red: 0.55, green: 0.1, blue: 0.2),
        "AFG": Color(red: 0.1, green: 0.4, blue: 0.85),
        "ZIM": Color(red: 0.85, green: 0.2, blue: 0.2),
        "IRE": Color(red: 0.15, green: 0.6, blue: 0.35),
    ]

    static func color(for team: Team) -> Color {
        if let color = known[team.shortName.uppercased()] { return color }
        // Stable (not randomised per launch) hash → hue.
        let sum = team.name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return Color(hue: Double(sum % 360) / 360, saturation: 0.55, brightness: 0.8)
    }
}

enum Format {
    static func rate(_ value: Double?) -> String? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return String(format: "%.2f", value)
    }

    static func strikeRate(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "–" }
        return String(format: "%.1f", value)
    }

    /// "in 42 min", "in 2 hr 5 min", "starting now".
    static func countdown(to date: Date, now: Date = Date()) -> String {
        let minutes = Int((date.timeIntervalSince(now) / 60).rounded(.up))
        if minutes <= 0 { return "Starting now" }
        if minutes < 60 { return "Starts in \(minutes) min" }
        let hours = minutes / 60, rest = minutes % 60
        if hours < 24 { return rest == 0 ? "Starts in \(hours) hr" : "Starts in \(hours) hr \(rest) min" }
        return "Starts \(date.formatted(.dateTime.weekday(.abbreviated).hour().minute()))"
    }

    static func compactCountdown(to date: Date, now: Date = Date()) -> String {
        let minutes = Int((date.timeIntervalSince(now) / 60).rounded(.up))
        if minutes <= 0 { return "now" }
        if minutes < 60 { return "\(minutes)m" }
        if minutes < 24 * 60 { return "\(minutes / 60)h \(minutes % 60)m" }
        return date.formatted(.dateTime.weekday(.abbreviated))
    }

    /// "7:30 PM" today, "Tomorrow 7:30 PM", or "Sat 7:30 PM".
    static func startTime(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return time }
        if calendar.isDateInTomorrow(date) { return "Tomorrow \(time)" }
        return "\(date.formatted(.dateTime.weekday(.abbreviated))) \(time)"
    }

    static func updatedAgo(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "Not updated yet" }
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 5 { return "Updated just now" }
        if seconds < 60 { return "Updated \(seconds) sec ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "Updated \(minutes) min ago" }
        return "Updated at \(date.formatted(date: .omitted, time: .shortened))"
    }

    /// "India won by 6 wickets" → "IND won by 6 wkts".
    static func shortResult(_ result: String, match: CricketMatch) -> String {
        var text = result
        for team in match.teams where text.hasPrefix(team.name) {
            text = team.shortName + text.dropFirst(team.name.count)
        }
        return text.replacingOccurrences(of: " wickets", with: " wkts")
            .replacingOccurrences(of: " wicket", with: " wkt")
    }
}

/// Animates changing numbers (184 → 185) with a rolling-digit transition.
struct NumericTransition: ViewModifier {
    let value: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content
                .contentTransition(.numericText(value: value))
                .animation(.snappy(duration: 0.35), value: value)
        }
    }
}

extension View {
    func numericTransition(_ value: Int) -> some View {
        modifier(NumericTransition(value: Double(value)))
    }
}

/// Behind-window blur (SwiftUI materials only blur within a window, and ours is transparent).
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}
