import SwiftUI

/// The bowler's row inside `PlayersTable`.
struct BowlerRow: View {
    let bowler: Bowler

    var body: some View {
        GridRow {
            Text(bowler.name)
                .font(Theme.label(12))
                .lineLimit(1)
                .padding(.leading, 11.5)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(bowler.oversText)
                .font(Theme.score(11, .regular))
                .foregroundStyle(.secondary)
            Text("\(bowler.maidens)")
                .font(Theme.score(11, .regular))
                .foregroundStyle(.secondary)
            Text("\(bowler.runs)")
                .font(Theme.score(11, .regular))
                .foregroundStyle(.secondary)
                .numericTransition(bowler.runs)
            Text("\(bowler.wickets)")
                .font(Theme.score(12.5, .bold))
                .numericTransition(bowler.wickets)
            Text(Format.rate(bowler.economy) ?? "–")
                .font(Theme.score(11, .regular))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bowling: \(bowler.name), \(bowler.oversText) overs, \(bowler.maidens) maidens, \(bowler.runs) runs, \(bowler.wickets) wickets")
    }
}
