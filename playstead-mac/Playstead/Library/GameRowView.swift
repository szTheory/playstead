import SwiftUI

/// A functional (not yet visually designed) row for one catalogue entry:
/// title and system only. The visual identity, shelves, sidebar, and
/// status vocabulary are plan 03-06's work against the UI spec (D-12
/// through D-17) — this row exists so the tracer can prove the read
/// path end to end.
struct GameRowView: View {
    let entry: CatalogueEntry

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayTitle)
                    .font(.headline)
                Text(entry.system)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
