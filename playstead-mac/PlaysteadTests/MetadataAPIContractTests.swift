import Foundation
import XCTest
@testable import Playstead

final class MetadataAPIContractTests: XCTestCase {
    private let credential = PairingCredential(
        deviceID: "metadata-test-device",
        baseURL: URL(string: "https://metadata.test")!,
        token: "metadata-test-token"
    )

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    func testConsentSendsOnlyDisclosedTitleAndSystemAndRevocationSendsNoBody() async throws {
        StubURLProtocol.responder = { _ in
            StubURLProtocol.Stub(statusCode: 204, headers: [:], body: Data())
        }
        let client = makeClient()
        let preview = MetadataProviderPreview(
            provider: "igdb", enabled: false, revision: 7, disclosureRevision: "igdb-terms-7",
            queryPreview: "Owner-selected title", system: "gb", titleWarning: nil,
            credentialsReady: true, attribution: "IGDB", termsURL: "https://example.test/terms",
            imageFetchAllowed: false, cacheAgeDays: 30
        )

        try await MetadataAPI.setConsent(client, assetSetID: "asset-1", preview: preview, enabled: true)
        try await MetadataAPI.setConsent(client, assetSetID: "asset-1", preview: preview, enabled: false)

        let requests = StubURLProtocol.requestLog
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].httpMethod, "POST")
        XCTAssertTrue(requests[0].url?.path.hasSuffix("/api/v1/metadata/asset-1/provider/consent") == true)
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer metadata-test-token")
        let body = try XCTUnwrap(Self.bodyData(for: requests[0]))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(payload, [
            "title": "Owner-selected title",
            "system": "gb",
            "disclosure_revision": "igdb-terms-7"
        ])
        XCTAssertNil(payload["hash"])
        XCTAssertNil(payload["filename"])

        XCTAssertEqual(requests[1].httpMethod, "DELETE")
        XCTAssertNil(requests[1].httpBody)
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer metadata-test-token")

        StubURLProtocol.responder = { request in
            XCTAssertEqual(request.httpMethod, "DELETE")
            return StubURLProtocol.Stub(statusCode: 200, headers: ["Content-Type": "application/json"],
                body: Data(#"{"enabled":false,"revision":8,"cache_cleanup":{"status":"failed","retryable":true}}"#.utf8))
        }
        do {
            try await MetadataAPI.setConsent(client, assetSetID: "asset-1", preview: preview, enabled: false)
            XCTFail("revocation must expose a failed cache cleanup")
        } catch MetadataAPIError.cacheCleanupPending {
            // Access was revoked; cleanup is a separate retryable outcome.
        } catch {
            XCTFail("unexpected revocation outcome: \(error)")
        }
        XCTAssertEqual(StubURLProtocol.requestLog.count, 3, "cleanup failure must never trigger provider search")
    }

    func testProviderSearchRejectionIsPreservedAsServerConsentGate() async throws {
        StubURLProtocol.responder = { request in
            XCTAssertTrue(request.url?.path.hasSuffix("/api/v1/metadata/asset-1/provider/search") == true)
            return StubURLProtocol.Stub(
                statusCode: 403, headers: ["Content-Type": "application/problem+json"],
                body: Data("{\"code\":\"provider_consent_required\"}".utf8)
            )
        }
        let client = makeClient()

        do {
            _ = try await MetadataAPI.search(client, assetSetID: "asset-1")
            XCTFail("server consent gate must reject the provider search")
        } catch let APIClientError.server(problem) {
            XCTAssertEqual(problem.status, 403)
            XCTAssertEqual(problem.code, "provider_consent_required")
        } catch {
            XCTFail("unexpected search error: \(error)")
        }
        XCTAssertEqual(StubURLProtocol.requestLog.count, 1)
    }

    func testPrivateMediaBoundsAndDecodeFailuresAreRejectedBeforeAnyRequest() async throws {
        let client = makeClient()
        let oversizedText = Data(repeating: 0x61, count: 65_537)
        let oversizedImage = Data(repeating: 0, count: MetadataAPI.maxPrivateMediaBytes + 1)

        for (bytes, mime) in [(Data(), "text/plain"), (Data("not an image".utf8), "image/png"),
                              (oversizedText, "text/plain"), (oversizedImage, "image/png")] {
            do {
                _ = try await MetadataAPI.uploadPrivateMedia(client, assetSetID: "asset-1", bytes: bytes, mime: mime)
                XCTFail("invalid private media must be rejected locally")
            } catch MetadataAPIError.invalidPrivateMedia {
                // Expected: untrusted media must be bounded and decoded before network I/O.
            } catch {
                XCTFail("unexpected upload error: \(error)")
            }
        }
        XCTAssertTrue(StubURLProtocol.requestLog.isEmpty, "invalid file bytes must never reach the server")
    }

    private func makeClient() -> APIClient {
        APIClient(keychain: KeychainStore(), pinnedCertificateURL: nil,
                  session: StubURLProtocol.makeSession(), credential: credential)
    }

    private static func bodyData(for request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
        defer { buffer.deallocate() }
        var body = Data()
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: 4096)
            if count <= 0 { break }
            body.append(buffer, count: count)
        }
        return body
    }
}
