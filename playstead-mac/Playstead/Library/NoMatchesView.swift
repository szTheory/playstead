import SwiftUI

/// The "no matches" explanatory result — never a blank pane
/// (03-UI-SPEC.md Copywriting Contract). Rendered by both library layouts
/// whenever `LibraryViewModel.searchResultState` is non-nil.
///
/// It lived for a long time in a file whose other contents nothing
/// instantiated, and was itself never rendered: a search that matched nothing
/// showed the empty-library pairing prompt instead (WINDOWS #83). It is here,
/// in its own file, because it is now on the shipped path.
struct NoMatchesView: View {
    let state: SearchResultState
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(state.heading).font(.psHeading).foregroundStyle(DesignTokens.textPrimary)
            Text(state.body).font(.psBody).foregroundStyle(DesignTokens.textMuted)
            Button(state.clearControlLabel, action: onClear)
                .accessibilityLabel(state.clearControlLabel)
                .accessibilityIdentifier(AccessibilityIdentifiers.Control.clearSearch)
        }
        .padding(DesignTokens.Spacing.lg)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityIdentifiers.Surface.noMatches)
    }
}
