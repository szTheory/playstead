import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// What `BiosDropTargetView` shows after handling one dropped file.
enum BiosDropResult: Equatable {
    case idle
    case accepted(BiosRecord)
    case rejected(reason: String)
}

/// The drop-handling logic behind `BiosDropTargetView`, kept free of
/// SwiftUI/`NSItemProvider` machinery so behavior is exercised directly
/// against a plain file URL rather than simulating a real drag session.
struct BiosDropTarget {
    let store: BiosStore
    let system: String

    @discardableResult
    func handle(droppedFileURL: URL) -> BiosDropResult {
        do {
            let record = try store.validateAndAccept(candidateURL: droppedFileURL, system: system)
            return .accepted(record)
        } catch {
            return .rejected(reason: Self.rejectionMessage(for: error))
        }
    }
}

private extension BiosDropTarget {
    static func rejectionMessage(for error: Error) -> String {
        guard let storeError = error as? BiosStoreError, case let .invalidCandidate(reason) = storeError else {
            return "This file could not be validated."
        }
        return "This file could not be validated — \(reason)."
    }
}

/// A drag-and-drop surface for a BIOS file the user already has. Its
/// copy never names a source, a link, or a filename hint for such a
/// file — the user either already has it or does not, and this view's
/// only job is to say what happened when they drop something.
struct BiosDropTargetView: View {
    let target: BiosDropTarget
    @State private var result: BiosDropResult = .idle
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.sm) {
            Text("Drop your BIOS file here to validate it.")
                .font(.psBody)
                .foregroundColor(DesignTokens.textPrimary)
            statusView
        }
        .padding(DesignTokens.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isTargeted ? DesignTokens.focusRing : DesignTokens.border, lineWidth: isTargeted ? 2 : 1)
        )
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted, perform: handleProviders)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusView: some View {
        switch result {
        case .idle:
            EmptyView()
        case .accepted:
            Text("BIOS validated and stored.")
                .font(.psLabel)
                .foregroundColor(StatusToken.verified)
        case .rejected(let reason):
            Text(reason)
                .font(.psLabel)
                .foregroundColor(StatusToken.attention)
        }
    }

    private func handleProviders(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            DispatchQueue.main.async {
                result = target.handle(droppedFileURL: url)
            }
        }
        return true
    }
}
