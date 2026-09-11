import Foundation

/// The production `BiosStore.Reference` set this app actually ships,
/// mirroring `.planning/phases/03-mac-offline-play-vertical-slice/03-BIOS-PIN.json`
/// literally — that pin file is the source of truth; these Swift
/// literals are its transcription, and `BiosProductionReferenceTests`
/// asserts the two cannot silently diverge.
///
/// Provenance for the pinned `gba` entry (both byte length and digest
/// independently corroborated by at least two sources each; see the pin
/// file's own `provenance` array for the full record):
/// - https://higan.readthedocs.io/en/stable/install/general/
/// - https://wiki.ds-homebrew.com/gbarunner2/bios
/// - https://problemkaputt.de/gbatek.htm
///
/// This product offers no acquisition path for BIOS content: it never
/// sources, links to, mirrors, or distributes it. A caller either
/// already has a legally-owned file or does not; this type only states
/// what a genuine one looks like.
enum BiosReferences {
    static let production: [BiosStore.Reference] = [
        BiosStore.Reference(
            system: "gba",
            expectedByteLength: 16384,
            knownSHA256Digests: [
                "fd2547724b505f487e6dcb29ec2ecff3af35a841a77ab2e85fd87350abd36570"
            ]
        )
    ]
}
