import SwiftUI

/// Posted by the app menu's "Pair with Server…" command (see
/// `PlaysteadApp`'s `.commands`) so an already-paired user can re-pair
/// against a new server from a second reachable call site, independent of
/// the empty-state action button `LibraryShellView` presents.
extension Notification.Name {
    static let presentPairingSheetRequested = Notification.Name("dev.playstead.mac.presentPairingSheetRequested")
}

/// The pairing ceremony surface, shaped after `AdapterSetupView`: a small
/// setup screen that drives a long-running async operation with progress
/// and typed failure states, rather than inventing a new shape.
///
/// This view owns no ceremony logic itself — every step (request, poll,
/// redeem, persist) lives in `PairingCoordinator`, which this view only
/// observes and drives. That split is deliberate (WINDOWS #37/#45's own
/// failure mode): a `private @MainActor` view method is a step no test can
/// drive.
struct PairingView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var coordinator: PairingCoordinator?
    @State private var serverURLText: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            if let coordinator {
                content(for: coordinator.state, coordinator: coordinator)
            } else {
                Text("Pairing is unavailable in this build.")
                    .font(.psBody)
                    .foregroundColor(DesignTokens.textPrimary)
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            if coordinator == nil {
                coordinator = environment.makePairingCoordinator()
            }
        }
        .onDisappear {
            // The user closing the sheet must stop the poll loop rather
            // than let it keep polling a request nothing will ever redeem.
            coordinator?.cancel()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pairing")
    }

    @ViewBuilder
    private func content(for state: PairingState, coordinator: PairingCoordinator) -> some View {
        switch state {
        case .idle:
            form(coordinator: coordinator, error: nil)
        case .failed(let error):
            form(coordinator: coordinator, error: error)
        case .requesting:
            ProgressView("Requesting…")
        case .awaitingApproval(let displayCode, _):
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                Text("Approve this code in your server's devices console:")
                    .font(.psBody)
                    .foregroundColor(DesignTokens.textPrimary)
                Text(displayCode)
                    .font(.system(.largeTitle, design: .monospaced))
                    .foregroundColor(DesignTokens.textPrimary)
                    .accessibilityIdentifier(AccessibilityIdentifiers.Control.pairingDisplayCode)
                ProgressView()
            }
        case .redeeming:
            ProgressView("Finishing pairing…")
        case .paired:
            Text("This Mac is paired.")
                .font(.psBody)
                .foregroundColor(DesignTokens.textPrimary)
                .accessibilityIdentifier(AccessibilityIdentifiers.Control.pairingSuccess)
        }
    }

    private func form(coordinator: PairingCoordinator, error: PairingError?) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("Enter your Playstead server's address to pair this Mac.")
                .font(.psBody)
                .foregroundColor(DesignTokens.textPrimary)
            TextField("https://your-server.example.com", text: $serverURLText)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier(AccessibilityIdentifiers.Control.pairingServerURL)
            if let error {
                Text(Self.describe(error))
                    .font(.psLabelEmphasized)
                    .foregroundColor(StatusToken.missingDependency)
            }
            Button("Request pairing") {
                let url = serverURLText
                Task { await coordinator.start(baseURLString: url) }
            }
            .disabled(serverURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier(AccessibilityIdentifiers.Control.requestPairing)
        }
    }

    /// Every server refusal is a distinct, actionable message — never a
    /// generic "pairing failed" (PROT-01/ceremony-failure).
    private static func describe(_ error: PairingError) -> String {
        switch error {
        case .expired:
            return "This pairing request expired. Request a new code."
        case .alreadyRedeemed:
            return "This code was already used to pair a device. Request a new code."
        case .notApproved:
            return "This pairing request has not been approved yet. Approve it in the server's devices console."
        case .slowDown:
            return "Polling too fast — slowing down automatically."
        case .notFound:
            return "This pairing request could not be found. Request a new code."
        case .denied:
            return "This pairing request was denied."
        case .keychainWriteFailed:
            return "Pairing succeeded, but the credential could not be saved to the Keychain."
        case .invalidResponse:
            return "The server address is not valid, or it sent an unexpected response."
        case .transport:
            return "Could not reach the server. Check the address and your connection."
        }
    }
}
