import CryptoKit
import Foundation

/// Cartridge and battery-save facts proven from the exact local ROM bytes.
/// The caller must also prove that those bytes match the requested content hash.
struct QualifiedCartridge: Equatable, Sendable {
    let systemID: String
    let cartridgeID: String
    let mediumID: String
    let artifactBytes: Int
    let saveFormat: String
    let romSHA256: String
}

struct CartridgeSupportDeclaration: Equatable, Sendable {
    let systemID: String
    let cartridgeID: String
    let cgbFlag: UInt8
    let cartridgeType: UInt8
    let ramSizeCode: UInt8
    let mediumID: String
    let artifactBytes: Int
    let saveFormat: String
}

enum CartridgeQualificationError: Error, Equatable {
    case unavailable
    case invalidFile
    case digestMismatch
    case invalidHeader
    case unsupportedCartridge
}

/// Bounded reader for the independently tested GB/GBC cartridge tuples. This
/// does not infer a game from its filename or title; only exact headers qualify.
enum CartridgeQualification {
    static let mbc1Declaration = CartridgeSupportDeclaration(
        systemID: "gb", cartridgeID: "mbc1", cgbFlag: 0x00,
        cartridgeType: 0x03, ramSizeCode: 0x02,
        mediumID: "gb_sram_8k", artifactBytes: 8_192,
        saveFormat: "mgba-0.10.5-gb-mbc1-sram-8k"
    )
    static let mbc5Declaration = CartridgeSupportDeclaration(
        systemID: "gbc", cartridgeID: "mbc5", cgbFlag: 0xC0,
        cartridgeType: 0x1B, ramSizeCode: 0x03,
        mediumID: "gbc_sram_32k", artifactBytes: 32_768,
        saveFormat: "mgba-0.10.5-gbc-mbc5-sram-32k"
    )
    static let mbc3RTCDeclaration = CartridgeSupportDeclaration(
        systemID: "gbc", cartridgeID: "mbc3-rtc", cgbFlag: 0xC0,
        cartridgeType: 0x10, ramSizeCode: 0x03,
        mediumID: "gbc_sram_32k_rtc", artifactBytes: 32_816,
        saveFormat: "mgba-0.10.5-gbc-mbc3-rtc-sram-32k-v1"
    )
    static let supportedDeclarations = [mbc1Declaration, mbc5Declaration, mbc3RTCDeclaration]
    private static let maximumROMBytes: UInt64 = 64 * 1024 * 1024
    private static let headerStart: UInt64 = 0x143
    private static let headerLength = 0x14D - 0x143 + 1

    static func qualify(romURL: URL, expectedSHA256: String) throws -> QualifiedCartridge {
        guard expectedSHA256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
            throw CartridgeQualificationError.invalidFile
        }
        guard (try? FileManager.default.destinationOfSymbolicLink(atPath: romURL.path)) == nil,
              let attributes = try? FileManager.default.attributesOfItem(atPath: romURL.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let size = (attributes[.size] as? NSNumber)?.uint64Value,
              size >= 0x150, size <= maximumROMBytes else {
            throw CartridgeQualificationError.unavailable
        }

        let handle: FileHandle
        do { handle = try FileHandle(forReadingFrom: romURL) }
        catch { throw CartridgeQualificationError.unavailable }
        defer { try? handle.close() }

        let header: Data
        do {
            try handle.seek(toOffset: headerStart)
            header = try handle.read(upToCount: headerLength) ?? Data()
        } catch {
            throw CartridgeQualificationError.unavailable
        }
        guard header.count == headerLength else { throw CartridgeQualificationError.invalidHeader }

        let checksum = (0x134...0x14C).reduce(UInt8(0)) { sum, offset in
            // The checksum range is below the fixed window and the file size
            // was checked before either read.
            let byteOffset = UInt64(offset)
            guard (try? handle.seek(toOffset: byteOffset)) != nil,
                  let byte = try? handle.read(upToCount: 1)?.first else { return sum }
            return sum &- byte &- 1
        }
        guard let storedChecksum = header.last, checksum == storedChecksum else {
            throw CartridgeQualificationError.invalidHeader
        }

        let digest: String
        do {
            try handle.seek(toOffset: 0)
            var hasher = SHA256()
            while true {
                let chunk = try handle.read(upToCount: 64 * 1024) ?? Data()
                if chunk.isEmpty { break }
                hasher.update(data: chunk)
            }
            digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        } catch {
            throw CartridgeQualificationError.unavailable
        }
        guard digest == expectedSHA256 else { throw CartridgeQualificationError.digestMismatch }

        let cgbFlag = header[0]
        let cartridgeType = header[4]
        let ramSizeCode = header[6]
        guard let declaration = supportedDeclarations.first(where: {
            $0.cgbFlag == cgbFlag && $0.cartridgeType == cartridgeType && $0.ramSizeCode == ramSizeCode
        }) else {
            throw CartridgeQualificationError.unsupportedCartridge
        }
        return QualifiedCartridge(
            systemID: declaration.systemID,
            cartridgeID: declaration.cartridgeID,
            mediumID: declaration.mediumID,
            artifactBytes: declaration.artifactBytes,
            saveFormat: declaration.saveFormat,
            romSHA256: digest
        )
    }
}
