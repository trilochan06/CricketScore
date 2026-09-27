import SwiftUI

/// Batters and the current bowler in one grid so their number columns line up.
struct PlayersTable: View {
    let batters: [Batter]
    let bowler: Bowler?
    var partnership: Partnership?

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 5) {
            if !batters.isEmpty {
                HeaderRow(title: "BATTER", columns: ["R", "B", "4s", "6s", "SR"])
                ForEach(batters) { BatterRow(batter: $0) }
                if let partnership, partnership.balls > 0 || partnership.runs > 0 {
                    GridRow {
                        Text("Partnership \(partnership.runs) (\(partnership.balls))")
                            .font(Theme.label(10.5))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .padding(.leading, 11.5)
                            .gridCellColumns(6)
                    }
                }
            }
            if let bowler {
                if !batters.isEmpty {
                    GridRow { Color.clear.frame(height: 4).gridCellColumns(6) }
                }
                HeaderRow(title: "BOWLER", columns: ["O", "M", "R", "W", "ECON"])
                BowlerRow(bowler: bowler)
            }
        }
    }
}

private struct HeaderRow: View {
    let title: String
    let columns: [String]

    var body: some View {
        GridRow {
            SectionLabel(title)
                .padding(.leading, 11.5)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(columns, id: \.self) { SectionLabel($0).gridColumnAlignment(.trailing) }
        }
    }
}

private struct BatterRow: View {
    let batter: Batter

    var body: some View {
        GridRow {
            HStack(spacing: 5) {
                Image(systemName: "arrowtriangle.right.fill")
                    .font(.system(size: 6.5))
                    .foregroundStyle(Theme.live)
                    .opacity(batter.isStriker ? 1 : 0)
                    .accessibilityHidden(true)
                Text(batter.name)
                    .font(Theme.label(12, batter.isStriker ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(batter.runs)")
                .font(Theme.score(12.5, .bold))
                .numericTransition(batter.runs)
            Text("\(batter.balls)")
                .font(Theme.score(11, .regular))
                .foregroundStyle(.secondary)
                .numericTransition(batter.balls)
            Text("\(batter.fours)").font(Theme.score(11, .regular)).foregroundStyle(.secondary)
            Text("\(batter.sixes)").font(Theme.score(11, .regular)).foregroundStyle(.secondary)
            Text(Format.strikeRate(batter.strikeRate)).font(Theme.score(11, .regular)).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(batter.name)\(batter.isStriker ? ", on strike" : ""), \(batter.runs) runs from \(batter.balls) balls, \(batter.fours) fours, \(batter.sixes) sixes")
    }
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Theme.sectionHeader)
            .foregroundStyle(.tertiary)
            .fixedSize()
    }
}
