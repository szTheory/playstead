import XCTest
import Security

@MainActor
final class HostedRunnerCanaryTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAdHocSignedAppLaunchesOnHostedRunner() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.windows.firstMatch.waitForExistence(timeout: 15),
            "The ad-hoc-signed Playstead app must launch and expose a window"
        )
        XCTAssertEqual(app.state, .runningForeground)
        app.terminate()
    }

    func testFullKeyboardAccessCanaryFocusesAndActivatesTwoControls() throws {
        let app = XCUIApplication()
        app.launch()

        let expected = [
            app.buttons["Download queue"],
            app.buttons["Storage and quota settings"],
            app.buttons["Adapter setup"]
        ]
        for element in expected {
            XCTAssertTrue(element.waitForExistence(timeout: 15))
        }

        // Establish a deterministic starting point without trusting the
        // defaults command. A bounded Tab search must actually observe the
        // first expected element focused on the live accessibility tree.
        var foundStart = hasKeyboardFocus(expected[0])
        for _ in 0..<20 where !foundStart {
            app.typeKey(.tab, modifierFlags: [])
            foundStart = hasKeyboardFocus(expected[0])
        }
        XCTAssertTrue(foundStart, "Full Keyboard Access never reached the first canary control")

        assertExactlyOneFocusedElement(in: app, expected: expected[0])
        for next in expected.dropFirst() {
            app.typeKey(.tab, modifierFlags: [])
            assertExactlyOneFocusedElement(in: app, expected: next)
        }
        app.typeKey(.tab, modifierFlags: [])
        assertExactlyOneFocusedElement(in: app, expected: expected[0])

        for previous in expected.reversed().dropLast() {
            app.typeKey(.tab, modifierFlags: [.shift])
            assertExactlyOneFocusedElement(in: app, expected: previous)
        }

        app.typeKey(.space, modifierFlags: [])
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5), "focused toolbar control did not activate")
        app.buttons["Done"].typeKey(.space, modifierFlags: [])
        XCTAssertFalse(app.buttons["Done"].waitForExistence(timeout: 2))
        app.terminate()
    }

    func testScopedFileKeychainStoresLoadsAndDeletesTwice() throws {
        let searchListBefore = try copyKeychainSearchList()

        for cycle in 0..<2 {
            let file = FileManager.default.temporaryDirectory
                .appendingPathComponent("playstead-wave0-\(UUID().uuidString).keychain-db")
            let password = Data("synthetic-wave0-\(UUID().uuidString)".utf8)
            var keychain: SecKeychain?
            let createStatus = file.path.withCString { path in
                password.withUnsafeBytes { bytes in
                    SecKeychainCreate(
                        path,
                        UInt32(password.count),
                        bytes.baseAddress,
                        false,
                        nil,
                        &keychain
                    )
                }
            }
            XCTAssertEqual(createStatus, errSecSuccess)
            guard let keychain else { return XCTFail("file Keychain was not created") }

            var keychainDeleted = false
            defer {
                if !keychainDeleted {
                    SecKeychainDelete(keychain)
                }
                try? FileManager.default.removeItem(at: file)
            }

            // XCUITest is an out-of-process bundle and must not link against
            // the app executable. Exercise the same Security.framework
            // destination/search-list contract directly here; the production
            // KeychainStore query builders are covered by KeychainScopingTests.
            let service = "dev.playstead.mac.wave0.\(cycle).\(UUID().uuidString)"
            let account = "synthetic-device-\(cycle)"
            let secret = Data("synthetic-token-\(cycle)".utf8)
            let addQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecValueData as String: secret,
                kSecUseKeychain as String: keychain
            ]
            XCTAssertEqual(SecItemAdd(addQuery as CFDictionary, nil), errSecSuccess)

            let matchQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecMatchSearchList as String: [keychain],
                kSecMatchLimit as String: kSecMatchLimitOne,
                kSecReturnData as String: true
            ]
            var loaded: CFTypeRef?
            XCTAssertEqual(SecItemCopyMatching(matchQuery as CFDictionary, &loaded), errSecSuccess)
            XCTAssertEqual(loaded as? Data, secret)

            let deleteQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecMatchSearchList as String: [keychain]
            ]
            XCTAssertEqual(SecItemDelete(deleteQuery as CFDictionary), errSecSuccess)
            loaded = nil
            XCTAssertEqual(
                SecItemCopyMatching(matchQuery as CFDictionary, &loaded),
                errSecItemNotFound
            )

            XCTAssertTrue(sameKeychainList(searchListBefore, try copyKeychainSearchList()))
            XCTAssertEqual(SecKeychainDelete(keychain), errSecSuccess)
            keychainDeleted = true
            XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        }

        XCTAssertTrue(sameKeychainList(searchListBefore, try copyKeychainSearchList()))
    }

    private func hasKeyboardFocus(_ element: XCUIElement) -> Bool {
        element.value(forKey: "hasKeyboardFocus") as? Bool == true
    }

    private func assertExactlyOneFocusedElement(in app: XCUIApplication, expected: XCUIElement) {
        let focused = app.descendants(matching: .any)
            .matching(NSPredicate(format: "hasKeyboardFocus == true"))
        XCTAssertEqual(focused.count, 1, "exactly one live element must own keyboard focus")
        XCTAssertTrue(hasKeyboardFocus(expected), "unexpected keyboard focus target")
    }

    private func copyKeychainSearchList() throws -> [SecKeychain] {
        var raw: CFArray?
        let status = SecKeychainCopySearchList(&raw)
        XCTAssertEqual(status, errSecSuccess)
        guard status == errSecSuccess, let list = raw as? [SecKeychain] else { return [] }
        return list
    }

    private func sameKeychainList(_ lhs: [SecKeychain], _ rhs: [SecKeychain]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { CFEqual($0, $1) }
    }
}
