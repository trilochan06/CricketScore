import Foundation

struct Delivery: Identifiable, Hashable, Sendable {
    enum Outcome: Hashable, Sendable {
        case dot
        case runs(Int)
        case four
        case six
        case wicket
        case wide(Int)
        case noBall(Int)
        case bye(Int)
        case legBye(Int)
    }

    enum Category: Sendable {
        case dot, runs, four, six, wicket, extra
    }

    /// Stable identifier so new balls can be detected and animated.
    let id: String
    let outcome: Outcome
    /// Zero-based over this ball belongs to, when known (used to draw over separators).
    var over: Int?

    var label: String {
        switch outcome {
        case .dot: "•"
        case .runs(let n): "\(n)"
        case .four: "4"
        case .six: "6"
        case .wicket: "W"
        case .wide(let n): n > 1 ? "\(n)wd" : "wd"
        case .noBall(let n): n > 1 ? "\(n)nb" : "nb"
        case .bye(let n): "\(n)b"
        case .legBye(let n): "\(n)lb"
        }
    }

    var category: Category {
        switch outcome {
        case .dot: .dot
        case .runs: .runs
        case .four: .four
        case .six: .six
        case .wicket: .wicket
        case .wide, .noBall, .bye, .legBye: .extra
        }
    }

    var isLegal: Bool {
        switch outcome {
        case .wide, .noBall: false
        default: true
        }
    }

    var accessibilityLabel: String {
        switch outcome {
        case .dot: "dot ball"
        case .runs(let n): n == 1 ? "1 run" : "\(n) runs"
        case .four: "four"
        case .six: "six"
        case .wicket: "wicket"
        case .wide(let n): n > 1 ? "wide, \(n) runs" : "wide"
        case .noBall(let n): n > 1 ? "no ball, \(n) runs" : "no ball"
        case .bye(let n): "\(n) bye"
        case .legBye(let n): "\(n) leg bye"
        }
    }
}
