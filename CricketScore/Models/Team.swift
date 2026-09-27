import Foundation

struct Team: Hashable, Sendable {
    /// Full name, e.g. "India".
    let name: String
    /// Abbreviation, e.g. "IND".
    let shortName: String

    init(name: String, shortName: String? = nil) {
        self.name = name
        self.shortName = shortName ?? Team.abbreviate(name)
    }

    static let unknown = Team(name: "TBC", shortName: "TBC")

    /// Best-effort abbreviation when a provider doesn't supply one.
    static func abbreviate(_ name: String) -> String {
        let words = name.split(separator: " ").filter { !$0.isEmpty }
        if words.count >= 2 {
            return String(words.prefix(3).compactMap(\.first)).uppercased()
        }
        return String(name.prefix(3)).uppercased()
    }
}
