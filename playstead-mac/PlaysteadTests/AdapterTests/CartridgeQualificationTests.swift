import Foundation
import XCTest
import Testing
import CryptoKit
@testable import Playstead

@Suite
struct CartridgeQualificationBehaviorSuite {
    private func makeMBC1ROM(cgbFlag: UInt8 = 0x00, cartridgeType: UInt8 = 0x03, ramCode: UInt8 = 0x02) throws -> (URL, Data, String) {
        var bytes = Data(repeating: 0, count: 32 * 1024)
        bytes[0x143] = cgbFlag
        bytes[0x147] = cartridgeType
        bytes[0x149] = ramCode
        let checksum = (0x134...0x14C).reduce(UInt8(0)) { sum, offset in
            sum &- bytes[offset] &- 1
        }
        bytes[0x14D] = checksum
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gb")
        try bytes.write(to: url)
        return (url, bytes, digest)
    }

    @Test
    func testCatalogAcceptsTheVerifiedGameBoyFixtureExtension() throws {
        let descriptor = AdapterCatalog(pin: try AdapterPin.load()).descriptor

        #expect(
            descriptor.acceptedContentTypes.contains(".gb"),
            "the pinned adapter catalog must include a separately qualified Game Boy capability"
        )
    }

    @Test
    func testQualifiedMBC1UsesGBAndAnIndependentEightKilobyteSaveIdentity() throws {
        let (rom, before, digest) = try makeMBC1ROM()
        defer { try? FileManager.default.removeItem(at: rom) }

        let capability = try CartridgeQualification.qualify(romURL: rom, expectedSHA256: digest)

        #expect(capability.systemID == "gb")
        #expect(capability.cartridgeID == "mbc1")
        #expect(capability.mediumID == "gb_sram_8k")
        #expect(capability.artifactBytes == 8_192)
        #expect(capability.saveFormat == CartridgeQualification.mbc1Declaration.saveFormat)
        #expect(capability.romSHA256 == digest)
        #expect(try Data(contentsOf: rom) == before)
    }

    @Test
    func testRejectsCandidateROMDigestThatDoesNotMatchItsBytes() throws {
        let (rom, _, _) = try makeMBC1ROM()
        defer { try? FileManager.default.removeItem(at: rom) }

        #expect(throws: CartridgeQualificationError.digestMismatch) {
            try CartridgeQualification.qualify(romURL: rom, expectedSHA256: String(repeating: "0", count: 64))
        }
    }

    @Test
    func testRejectsUnqualifiedDualModeAndUnknownCartridgeHeaders() throws {
        let (dualROM, _, dualDigest) = try makeMBC1ROM(cgbFlag: 0x80)
        defer { try? FileManager.default.removeItem(at: dualROM) }
        let (unknownROM, _, unknownDigest) = try makeMBC1ROM(cartridgeType: 0x19)
        defer { try? FileManager.default.removeItem(at: unknownROM) }

        #expect(throws: CartridgeQualificationError.unsupportedCartridge) {
            try CartridgeQualification.qualify(romURL: dualROM, expectedSHA256: dualDigest)
        }
        #expect(throws: CartridgeQualificationError.unsupportedCartridge) {
            try CartridgeQualification.qualify(romURL: unknownROM, expectedSHA256: unknownDigest)
        }
    }

    @Test
    func testRejectsTruncatedHeaderBeforeReadingBeyondTheFile() throws {
        let rom = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gb")
        let bytes = Data(repeating: 0, count: 0x149)
        try bytes.write(to: rom)
        defer { try? FileManager.default.removeItem(at: rom) }
        let digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()

        #expect(throws: CartridgeQualificationError.unavailable) {
            try CartridgeQualification.qualify(romURL: rom, expectedSHA256: digest)
        }
    }

    @Test
    func testRejectsCorruptHeaderChecksumAndKeepsROMBytesUnchanged() throws {
        let (rom, original, _) = try makeMBC1ROM()
        defer { try? FileManager.default.removeItem(at: rom) }
        var corrupt = original
        corrupt[0x14D] ^= 0x01
        try corrupt.write(to: rom)
        let digest = SHA256.hash(data: corrupt).map { String(format: "%02x", $0) }.joined()

        #expect(throws: CartridgeQualificationError.invalidHeader) {
            try CartridgeQualification.qualify(romURL: rom, expectedSHA256: digest)
        }
        #expect(try Data(contentsOf: rom) == corrupt)
    }

    @Test
    func testGameBoyQualificationLeavesPinnedGBAPinFactsUnchanged() throws {
        let pin = try AdapterPin.load()
        let descriptor = AdapterCatalog(pin: pin).descriptor

        #expect(pin.system == "gba")
        #expect(pin.emulator == "mgba")
        #expect(pin.version == "0.10.5")
        #expect(descriptor.supportedSystemIDs.contains("gba"))
        #expect(descriptor.supportedSystemIDs.contains("gb"))
        #expect(pin.saveContract.media?.contains(where: { $0.id == "sram_32k" && $0.bytes == 32_768 }) == true)
    }

}

final class CartridgeQualificationTests: XCTestCase {
    func testQualifiedMBC5MBC3AndDualModeBlock() throws {
        let cases: [(UInt8, UInt8, UInt8, String, String, String, Int, String)] = [
            (0x00, 0x03, 0x02, "gb", "mbc1", "gb_sram_8k", 8_192, "mgba-0.10.5-gb-mbc1-sram-8k"),
            (0xC0, 0x1B, 0x03, "gbc", "mbc5", "gbc_sram_32k", 32_768, "mgba-0.10.5-gbc-mbc5-sram-32k"),
            (0xC0, 0x10, 0x03, "gbc", "mbc3-rtc", "gbc_sram_32k_rtc", 32_816, "mgba-0.10.5-gbc-mbc3-rtc-sram-32k-v1")
        ]

        for (cgbFlag, cartridgeType, ramCode, system, cartridge, medium, bytes, format) in cases {
            var romBytes = Data(repeating: 0, count: 32 * 1024)
            romBytes[0x143] = cgbFlag
            romBytes[0x147] = cartridgeType
            romBytes[0x149] = ramCode
            romBytes[0x14D] = (0x134...0x14C).reduce(UInt8(0)) { $0 &- romBytes[$1] &- 1 }
            let rom = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gbc")
            try romBytes.write(to: rom)
            defer { try? FileManager.default.removeItem(at: rom) }
            let digest = SHA256.hash(data: romBytes).map { String(format: "%02x", $0) }.joined()

            let qualified = try? CartridgeQualification.qualify(romURL: rom, expectedSHA256: digest)
            XCTAssertEqual(qualified?.systemID, system)
            XCTAssertEqual(qualified?.cartridgeID, cartridge)
            XCTAssertEqual(qualified?.mediumID, medium)
            XCTAssertEqual(qualified?.artifactBytes, bytes)
            XCTAssertEqual(qualified?.saveFormat, format)
            XCTAssertEqual(try Data(contentsOf: rom), romBytes)
        }

        var dualMode = Data(repeating: 0, count: 32 * 1024)
        dualMode[0x143] = 0x80
        dualMode[0x147] = 0x1B
        dualMode[0x149] = 0x03
        dualMode[0x14D] = (0x134...0x14C).reduce(UInt8(0)) { $0 &- dualMode[$1] &- 1 }
        let dualROM = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gbc")
        try dualMode.write(to: dualROM)
        defer { try? FileManager.default.removeItem(at: dualROM) }
        let dualDigest = SHA256.hash(data: dualMode).map { String(format: "%02x", $0) }.joined()
        XCTAssertThrowsError(try CartridgeQualification.qualify(romURL: dualROM, expectedSHA256: dualDigest)) { error in
            XCTAssertEqual(error as? CartridgeQualificationError, .unsupportedCartridge)
        }
    }
}
