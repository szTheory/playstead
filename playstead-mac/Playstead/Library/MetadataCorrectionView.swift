import SwiftUI

struct MetadataCorrectionView: View {
    let entry: CatalogueEntry
#if UI_TESTING
    private let fixture: MetadataCorrectionStateFixture?
#endif
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var descriptionText = ""
    @State private var message: String?
    @State private var isSubmitting = false
    @State private var originalTitle = ""
    @State private var originalDescription = ""

#if UI_TESTING
    init(entry: CatalogueEntry, fixture: MetadataCorrectionStateFixture? = nil) {
        self.entry = entry
        self.fixture = fixture
        _title = State(initialValue: fixture?.title ?? "")
        _descriptionText = State(initialValue: fixture?.descriptionText ?? "")
        _message = State(initialValue: fixture?.message)
        _isSubmitting = State(initialValue: fixture?.isSubmitting ?? false)
    }
#endif

    private var selection: MetadataSelection? { environment.metadataSelection(for: entry.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("Correct metadata").font(.psHeading)
#if UI_TESTING
            if let fixture {
                Text(fixture.fixtureIdentity ?? "").accessibilityIdentifier("playstead.metadata.fixture.identity")
                Button("Next metadata fixture") { environment.advanceUITestMetadataFixture() }
                    .accessibilityIdentifier("playstead.metadata.fixture.next")
            }
#endif
            Text("These edits belong to your private library and can queue while offline.").font(.psBody).foregroundStyle(DesignTokens.textMuted)
            TextField("Title", text: $title).accessibilityIdentifier("playstead.metadata.correction.title")
            sourceLabel(for: "title")
            TextField("Description", text: $descriptionText, axis: .vertical).lineLimit(3...8)
                .accessibilityIdentifier("playstead.metadata.correction.description")
            sourceLabel(for: "description")
            conflictControls
            providerEvidenceControls
            HStack {
                Button("Save corrections") { save() }.disabled(isSubmitting || !hasChanges)
                    .accessibilityIdentifier("playstead.metadata.correction.save")
                Button("Cancel", role: .cancel) { dismiss() }
            }
            if let message { Text(message).font(.psLabel).accessibilityIdentifier("playstead.metadata.correction.status") }
        }
        .padding(DesignTokens.Spacing.xl)
        .frame(minWidth: 520, minHeight: 420)
        .task { loadSelectionValues() }
        .onChange(of: environment.metadataRefreshVersion) { _, _ in
            if !hasChanges { loadSelectionValues() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("playstead.metadata.correction.form")
    }

    private var hasChanges: Bool { title != originalTitle || descriptionText != originalDescription }

    private func loadSelectionValues() {
        let storedTitle = selection?.selections["title"]?.stringValue ?? environment.displayTitle(for: entry)
        let storedDescription = selection?.description ?? ""
        var initialTitle = storedTitle
#if UI_TESTING
        if fixture?.fixtureIdentity == "metadata-corrections/failed-submit" { initialTitle = fixture?.title ?? storedTitle }
#endif
        title = initialTitle
        descriptionText = storedDescription
        originalTitle = storedTitle
        originalDescription = storedDescription
    }

    @ViewBuilder private var providerEvidenceControls: some View {
        let current = selection
        ForEach(["title", "description"], id: \.self) { field in
            let source = current?.fieldSources[field]
            let selectedEvidenceID = evidenceID(source)
            let fieldChoices = (current?.evidence ?? [:]).compactMap { evidenceID, value -> (String, String, String)? in
                guard case .object(let fields) = value,
                      let providerValue = fields[field]?.stringValue, !providerValue.isEmpty,
                      selectedEvidenceID != evidenceID else { return nil }
                return (evidenceID, providerValue, fields["provider"]?.stringValue ?? fields["attribution"]?.stringValue ?? "Provider")
            }.sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
            ForEach(fieldChoices, id: \.0) { choice in
                Button("Reset \(field) to \(choice.2): \(choice.1)") {
                    Task { await resetToProvider(field: field, evidenceID: choice.0) }
                }
                .accessibilityIdentifier("playstead.metadata.correction.reset-provider.\(field).\(choice.0)")
            }
        }
    }

    @ViewBuilder private var conflictControls: some View {
        let conflicts = selection?.conflicts ?? []
        ForEach(Array(conflicts.enumerated()), id: \.offset) { _, conflict in
            if case .object(let fields) = conflict, let field = fields["field"]?.stringValue {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Concurrent change for \(field)").font(.psLabel)
                    Text("Your edit: \(alternativeValue(fields["incoming_alternative"]))")
                    Text("Current server value: \(alternativeValue(fields["current_alternative"]))")
                    HStack {
                        Button("Keep current") { resolve(field: field, value: alternativeValue(fields["current_alternative"])) }
                        Button("Keep my edit") { resolve(field: field, value: alternativeValue(fields["incoming_alternative"])) }
                    }
                }.accessibilityIdentifier("playstead.metadata.correction.conflict.\(field)")
            }
        }
        if !conflicts.isEmpty {
            Text("Choose a value explicitly. Neither alternative is discarded automatically.")
                .font(.psLabel).accessibilityIdentifier("playstead.metadata.correction.conflict.notice")
        }
    }

    @ViewBuilder private func sourceLabel(for field: String) -> some View {
        let source = selection?.fieldSources[field]
        HStack {
            Text("\(field.capitalized) source: \(sourceName(source)) · revision \(selection?.fieldRevisions[field] ?? 0)")
                .font(.psLabel).foregroundStyle(DesignTokens.textMuted)
                .accessibilityIdentifier("playstead.metadata.correction.source.\(field)")
            if let evidenceID = evidenceID(source) {
                Button("Reset to provider") { Task { await resetToProvider(field: field, evidenceID: evidenceID) } }
                    .accessibilityIdentifier("playstead.metadata.correction.reset-provider.\(field)")
            }
        }
    }

    private func sourceName(_ source: JSONValue?) -> String {
        if source?.stringValue == "user" { return "your private library" }
        if case .object(let values)? = source {
            if values["source"]?.stringValue == "user" { return "your private library" }
            if let provider = values["provider"]?.stringValue { return provider }
        }
        return "imported title or no description"
    }

    private func alternativeValue(_ alternative: JSONValue?) -> String {
        guard case .object(let fields)? = alternative else { return alternative?.stringValue ?? "(empty)" }
        return fields["value"]?.stringValue ?? "(empty)"
    }

    private func evidenceID(_ source: JSONValue?) -> String? {
        guard case .object(let values)? = source else { return nil }
        return values["evidence_id"]?.stringValue
    }

    @MainActor private func resetToProvider(field: String, evidenceID: String) async {
        do {
            _ = try await environment.metadataCoordinator.selectProviderEvidence(assetSetID: entry.id, field: field, evidenceID: evidenceID)
            message = "Current provider value selected with source and terms preserved."
        } catch { message = "Provider evidence expired or is no longer current. No value was changed." }
    }

    private func save() {
        let changedTitle = title != originalTitle
        let changedDescription = descriptionText != originalDescription
        guard changedTitle || changedDescription else { return }
        isSubmitting = true
        do {
            if changedTitle {
                _ = try environment.metadataCoordinator.correction(assetSetID: entry.id, field: "title", value: .string(title))
            }
            if changedDescription {
                _ = try environment.metadataCoordinator.correction(assetSetID: entry.id, field: "description", value: .string(descriptionText))
            }
            message = environment.reachability.isOnline ? "Corrections queued for server delivery." : "Corrections saved offline and queued for reconnection."
            dismiss()
        } catch { message = "The corrections could not be saved. Try again." }
        isSubmitting = false
    }

    private func resolve(field: String, value: String) {
        do {
            _ = try environment.metadataCoordinator.correction(assetSetID: entry.id, field: field, value: .string(value))
            message = "Resolution saved as a new explicit correction."
        } catch { message = "Resolution could not be saved." }
    }
}

#if UI_TESTING
struct MetadataCorrectionStateFixture {
    var title = ""
    var descriptionText = ""
    var message: String? = nil
    var isSubmitting = false
    var fixtureIdentity: String? = nil
}
#endif
