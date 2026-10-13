import XCTest
@testable import Playstead

/// Covers D-18/D-19/D-20/D-22/D-24: the three-tier, zero-network
/// compatibility gate, and the additive `AdapterSaveContract` fields
/// decoding safely against an older pin.
final class SaveCompatibilityGateTests: XCTestCase {
    func testDisplayedDiagnosticIsLiteralAndBoundedTo256Characters() {
        let hostile = String(repeating: "[evil](https://invalid.example)🔥\n", count: 100)
        let displayed = ReadinessReportView.boundedDiagnostic(hostile)

        XCTAssertEqual(displayed.count, 256)
        XCTAssertTrue(displayed.hasSuffix("…"))
        XCTAssertEqual(String(displayed.dropLast()), String(hostile.prefix(255)))
    }

    func testHistoryDeviceSubjectIsLiteralAndBounded() {
        let value = String(repeating: "Remote [device](https://invalid.example) 🕹️\n", count: 20)
        let shown = SaveHistorySheet.boundedSubject(value)
        XCTAssertEqual(shown.count, 120)
        XCTAssertTrue(shown.hasSuffix("…"))
        XCTAssertEqual(String(shown.dropLast()), String(value.prefix(119)))
    }

    @MainActor
    func testRowActionGateStartsOnlyOneConcurrentOperation() {
        let gate = GameRowActionGate()
        var submittedOperations = 0

        if gate.begin() { submittedOperations += 1 }
        if gate.begin() { submittedOperations += 1 }

        XCTAssertEqual(submittedOperations, 1)
        XCTAssertTrue(gate.isInFlight)
        gate.finish()
        XCTAssertTrue(gate.begin(), "a completed operation may be retried")
        XCTAssertEqual(submittedOperations, 1, "the duplicate attempt did not reach the operation counter")
    }

    // MARK: - Fixtures

    private static let provenance = SaveProvenance(
        emulator: "mgba", emulatorVersion: "0.10.5", coreVersion: nil,
        adapterPinSHA256: "aaaa", capturedAt: "2026-01-01T00:00:00Z", deviceID: "device-a"
    )

    private static let sameTitleGroup = SaveTitleIdentity(
        status: .matched, confidence: .exact, titleGroupID: "pokemon-emerald"
    )

    private func binding(
        systemID: String = "gba",
        saveKind: String = "battery",
        mediumID: String? = "sram_32k",
        artifactBytes: Int = 32768,
        romSHA256: String = "rom-a",
        titleIdentity: SaveTitleIdentity? = nil,
        origin: String = "emulated",
        provenance: SaveProvenance = SaveCompatibilityGateTests.provenance,
        saveFormat: String? = nil,
        formatConfidence: String? = nil
    ) -> SaveBinding {
        SaveBinding(
            systemID: systemID, saveKind: saveKind, mediumID: mediumID, artifactBytes: artifactBytes,
            romSHA256: romSHA256, titleIdentity: titleIdentity, origin: origin, provenance: provenance,
            saveFormat: saveFormat, formatConfidence: formatConfidence
        )
    }

    private func loadShippedContract() throws -> AdapterSaveContract {
        try AdapterPin.load().saveContract
    }

    private func gate() throws -> SaveCompatibilityGate {
        SaveCompatibilityGate(saveContract: try loadShippedContract())
    }

    // MARK: - Behaviours

    func testOlderPinLackingEveryNewSaveContractKeyDecodesWithNilFields() throws {
        let json = """
        {
          "artifact_glob": "{saveDir}/{romBaseName}.sav",
          "directory_key": "savegamePath",
          "flush_triggers": ["periodic_during_play_observed_every_24s"],
          "on_demand_flush_supported": false,
          "worst_case_loss_seconds": 24
        }
        """
        let contract = try JSONDecoder().decode(AdapterSaveContract.self, from: Data(json.utf8))

        XCTAssertNil(contract.saveKind)
        XCTAssertNil(contract.media)
        XCTAssertNil(contract.sizeIsMediumIdentity)
        XCTAssertNil(contract.acceptsForeignMedium)
        XCTAssertNil(contract.portableAcrossEmulators)
        XCTAssertNil(contract.maxArtifactBytes)
        XCTAssertNil(contract.provenMedia)
        XCTAssertNil(contract.bindingFields)
        XCTAssertNil(contract.provenanceFields)
    }

    func testShippedPinDecodesTheNewOptionalFieldsPopulated() throws {
        let contract = try loadShippedContract()

        XCTAssertEqual(contract.saveKind, "battery")
        XCTAssertEqual(contract.provenMedia, ["sram_32k"])
        XCTAssertEqual(contract.maxArtifactBytes, 131072)
        XCTAssertTrue(contract.media?.contains(where: { $0.id == "sram_32k" && $0.bytes == 32768 }) ?? false)
    }

    func testIdenticalBindingTupleYieldsExact() throws {
        let a = binding()
        let b = binding()
        XCTAssertEqual(try gate().evaluate(candidate: a, target: b), .exact)
    }

    func testSameTitleDifferentRomWithCertainMatchOnBothSidesYieldsSameTitle() throws {
        let candidate = binding(romSHA256: "rom-a", titleIdentity: Self.sameTitleGroup)
        let target = binding(romSHA256: "rom-b", titleIdentity: Self.sameTitleGroup)
        XCTAssertEqual(try gate().evaluate(candidate: candidate, target: target), .sameTitle)
    }

    func testSameTitleWithVariantConfidenceOnEitherSideIsIncompatible() throws {
        let variantOnOneSide = SaveTitleIdentity(status: .matched, confidence: .approximate, titleGroupID: "pokemon-emerald")
        let candidate = binding(romSHA256: "rom-a", titleIdentity: variantOnOneSide)
        let target = binding(romSHA256: "rom-b", titleIdentity: Self.sameTitleGroup)

        guard case .incompatible = try gate().evaluate(candidate: candidate, target: target) else {
            return XCTFail("a :variant-confidence reading on either side must never widen the gate")
        }
    }

    func testSameTitleWithNoMatchOnEitherSideIsIncompatible() throws {
        let noMatch = SaveTitleIdentity(status: .noMatch, confidence: .exact, titleGroupID: "")
        let candidate = binding(romSHA256: "rom-a", titleIdentity: noMatch)
        let target = binding(romSHA256: "rom-b", titleIdentity: Self.sameTitleGroup)

        guard case .incompatible = try gate().evaluate(candidate: candidate, target: target) else {
            return XCTFail(":no_match must never widen the gate")
        }
    }

    func testSameTitleWithAbsentTitleIdentityOnEitherSideIsIncompatible() throws {
        let candidate = binding(romSHA256: "rom-a", titleIdentity: nil)
        let target = binding(romSHA256: "rom-b", titleIdentity: Self.sameTitleGroup)

        guard case .incompatible = try gate().evaluate(candidate: candidate, target: target) else {
            return XCTFail("an absent title-identity reading must never widen the gate")
        }
    }

    func testDifferingMediumIDIsIncompatibleRegardlessOfEveryOtherFieldMatching() throws {
        let candidate = binding(mediumID: "sram_32k", artifactBytes: 32768)
        let target = binding(mediumID: "flash_64k", artifactBytes: 32768)

        guard case .incompatible(let reason) = try gate().evaluate(candidate: candidate, target: target) else {
            return XCTFail("a medium_id mismatch must be a hard block")
        }
        XCTAssertEqual(reason, "medium_mismatch")
    }

    func testDifferingArtifactBytesIsIncompatibleRegardlessOfEveryOtherFieldMatching() throws {
        let candidate = binding(artifactBytes: 32768)
        let target = binding(artifactBytes: 65536)

        guard case .incompatible(let reason) = try gate().evaluate(candidate: candidate, target: target) else {
            return XCTFail("an artifact_bytes mismatch must be a hard block")
        }
        XCTAssertEqual(reason, "artifact_bytes_mismatch")
    }

    func testUnboundMediumOnEitherSideIsIncompatible() throws {
        let candidate = binding(mediumID: nil)
        let target = binding(mediumID: "sram_32k")

        guard case .incompatible = try gate().evaluate(candidate: candidate, target: target) else {
            return XCTFail("an unbound (nil) medium must never restore")
        }
    }

    func testDifferentSystemIsIncompatible() throws {
        let candidate = binding(systemID: "gba")
        let target = binding(systemID: "gb")
        guard case .incompatible(let reason) = try gate().evaluate(candidate: candidate, target: target) else {
            return XCTFail("a different system must be a hard block")
        }
        XCTAssertEqual(reason, "different_system")
    }

    func testDifferentSaveKindIsIncompatible() throws {
        let candidate = binding(saveKind: "battery")
        let target = binding(saveKind: "state")
        guard case .incompatible(let reason) = try gate().evaluate(candidate: candidate, target: target) else {
            return XCTFail("a different save_kind must be a hard block")
        }
        XCTAssertEqual(reason, "different_save_kind")
    }

    func testDifferingEmulatorCoreOrVersionWithEverythingElseIdenticalStillYieldsExact() throws {
        let candidateProvenance = SaveProvenance(
            emulator: "mgba", emulatorVersion: "0.9.0", coreVersion: "core-x",
            adapterPinSHA256: "bbbb", capturedAt: "2025-01-01T00:00:00Z", deviceID: "device-b"
        )
        let candidate = binding(provenance: candidateProvenance)
        let target = binding(provenance: Self.provenance)

        XCTAssertEqual(try gate().evaluate(candidate: candidate, target: target), .exact)
    }

    func testGateMakesZeroNetworkCallsOnEveryPath() throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FailOnAnyRequestURLProtocol.self]
        FailOnAnyRequestURLProtocol.requestCount = 0

        let candidate = binding(romSHA256: "rom-a", titleIdentity: Self.sameTitleGroup)
        let target = binding(romSHA256: "rom-b", titleIdentity: Self.sameTitleGroup)
        _ = try gate().evaluate(candidate: candidate, target: binding(mediumID: "flash_64k"))
        _ = try gate().evaluate(candidate: candidate, target: target)
        _ = try gate().evaluate(candidate: binding(), target: binding())

        XCTAssertEqual(FailOnAnyRequestURLProtocol.requestCount, 0)
    }

    func testQualifiedMediumAndWrongBindingsRejectBeforeWrite() throws {
        let format = CartridgeQualification.mbc1Declaration.saveFormat
        let declaredFormats: Set<String> = [format]
        let gate = SaveCompatibilityGate(saveContract: try loadShippedContract(), declaredSaveFormats: declaredFormats)
        let exact = binding(
            systemID: "gb", mediumID: "gb_sram_8k", artifactBytes: 8_192,
            romSHA256: "same-rom", saveFormat: format, formatConfidence: "exact"
        )
        XCTAssertEqual(try gate.evaluate(candidate: exact, target: exact), .exact)

        // Equal size and two agreeing candidate claims still cannot promote
        // a GBA-only medium into an authorized GB target.
        let undeclaredMedium = binding(
            systemID: "gb", mediumID: "eeprom_8k", artifactBytes: 8_192,
            romSHA256: "same-rom", saveFormat: format, formatConfidence: "exact"
        )
        guard case .incompatible = try gate.evaluate(candidate: undeclaredMedium, target: undeclaredMedium) else {
            return XCTFail("matching but undeclared medium must be rejected before any target write")
        }

        let wrongFormat = binding(
            systemID: "gb", mediumID: "gb_sram_8k", artifactBytes: 8_192,
            romSHA256: "same-rom", saveFormat: "mgba-0.10.5-gba-eeprom-8k", formatConfidence: "exact"
        )
        guard case .incompatible = try gate.evaluate(candidate: wrongFormat, target: exact) else {
            return XCTFail("a mismatched source format must be rejected before any target write")
        }
    }

    func testQualifiedFormatConfidenceRemainsProvenanceOnly() throws {
        let declaration = CartridgeQualification.mbc5Declaration
        let source = binding(
            systemID: declaration.systemID, mediumID: declaration.mediumID, artifactBytes: declaration.artifactBytes,
            saveFormat: declaration.saveFormat, formatConfidence: "reported"
        )
        let target = binding(
            systemID: declaration.systemID, mediumID: declaration.mediumID, artifactBytes: declaration.artifactBytes,
            saveFormat: declaration.saveFormat, formatConfidence: "exact"
        )

        XCTAssertEqual(try gate().evaluate(candidate: source, target: target), .exact)
    }
}

/// A `URLProtocol` that fails the test on any request at all — used to
/// assert `SaveCompatibilityGate` never issues a network call, on any
/// path. Registering the protocol class alone does not intercept
/// anything unless a request is actually made through a session
/// configured with it; the counter proves none was.
final class FailOnAnyRequestURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestCount = 0

    override class func canInit(with request: URLRequest) -> Bool {
        requestCount += 1
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.unknown))
    }

    override func stopLoading() {}
}
