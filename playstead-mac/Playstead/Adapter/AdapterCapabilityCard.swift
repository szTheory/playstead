import Foundation
import SwiftUI

/// Renders the adapter descriptor honestly: system, emulator version,
/// digest, accepted content, BIOS posture (including the fidelity caveat
/// when the built-in high-level implementation is in use with no BIOS
/// present), persistent-save support, and whether the current
/// installation's digest actually matches the pin. Where the spike
/// recorded a limitation, this card states it — it never overstates what
/// the adapter supports.
struct AdapterCapabilityCard: Equatable {
    let descriptor: AdapterDescriptor
    let installState: AdapterInstallState
    /// Whether a validated BIOS is currently in managed storage
    /// (`BiosStore`, plan 03-09 task 2). Defaults to `false` — a card
    /// built before any BIOS has been evaluated correctly renders the
    /// no-BIOS caveat.
    var hasManagedBIOS: Bool = false
    /// How this installation got here. A downloaded install had its
    /// archive checked against the pin; a user-selected build never had
    /// an archive to check, so the card must not restate the pinned
    /// build's support claims for it.
    var provenance: AdapterProvenance = .pinnedRelease

    /// Shown whenever no BIOS is present and the adapter's built-in
    /// high-level implementation covers the system — so a user who later
    /// notices a fidelity difference recognises it as expected rather
    /// than suspecting corruption.
    static let noBiosFidelityCaveat = "Playing without a BIOS file. This adapter's built-in system BIOS is used instead — fidelity may differ from original hardware. This is expected, not a corruption."

    var systemText: String { descriptor.system.uppercased() }
    var emulatorVersionText: String { "\(descriptor.emulatorName) \(descriptor.version)" }
    var digestText: String { descriptor.expectedSHA256 }
    var acceptedContentText: String { descriptor.acceptedContentTypes.joined(separator: ", ") }

    var biosPostureText: String {
        if hasManagedBIOS {
            return "BIOS validated and in use."
        }
        if descriptor.biosRequired {
            return "BIOS required — none validated yet."
        }
        return Self.noBiosFidelityCaveat
    }

    var saveSupportText: String {
        let onDemand = descriptor.saveContract.onDemandFlushSupported ? "supported" : "not supported"
        return "Battery save persists automatically during play. On-demand save is \(onDemand)."
    }

    var installationLabelText: String {
        switch installState {
        case .notInstalled:
            return "Not installed."
        case .installed(_, let verified):
            guard verified else {
                return "Installed, but unverified — this installation has no recorded digest to re-check on launch. Support claims for the pinned build do not apply."
            }
            switch provenance {
            case .pinnedRelease:
                return "Installed and verified — matches the pinned release."
            case .userSelected:
                return "Installed, but unverified against the pinned release — this is a build you selected, re-checked against its own recorded digest on every launch. Support claims for the pinned build may not apply."
            }
        }
    }

    /// Every fact this card states, concatenated for a single
    /// substring-search assertion.
    var renderedText: String {
        [
            systemText, emulatorVersionText, digestText, acceptedContentText,
            biosPostureText, saveSupportText, installationLabelText
        ].joined(separator: "\n")
    }
}

extension AdapterCapabilityCard {
    /// Derives `hasManagedBIOS` from `BiosStore` rather than requiring
    /// every caller to query it separately (plan 03-09 task 2).
    init(
        descriptor: AdapterDescriptor,
        installState: AdapterInstallState,
        provenance: AdapterProvenance = .pinnedRelease,
        biosStore: BiosStore
    ) {
        self.init(
            descriptor: descriptor,
            installState: installState,
            hasManagedBIOS: biosStore.hasManagedBIOS(forSystem: descriptor.system),
            provenance: provenance
        )
    }
}

struct AdapterCapabilityCardView: View {
    let card: AdapterCapabilityCard

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("Adapter")
                .font(.psHeading)
                .foregroundColor(DesignTokens.textPrimary)
            Group {
                Text(card.systemText)
                Text(card.emulatorVersionText)
                Text("Digest: \(card.digestText)")
                Text("Accepts: \(card.acceptedContentText)")
            }
            .font(.psLabel)
            .foregroundColor(DesignTokens.textMuted)
            Text(card.biosPostureText)
                .font(.psBody)
                .foregroundColor(DesignTokens.textPrimary)
            Text(card.saveSupportText)
                .font(.psBody)
                .foregroundColor(DesignTokens.textPrimary)
            Text(card.installationLabelText)
                .font(.psLabelEmphasized)
                .foregroundColor(DesignTokens.textPrimary)
        }
        .padding(DesignTokens.Spacing.md)
        .accessibilityElement(children: .combine)
    }
}
