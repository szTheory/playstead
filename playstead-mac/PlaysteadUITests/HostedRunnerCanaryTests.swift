import XCTest
import Security

@MainActor
final class HostedRunnerCanaryTests: XCTestCase {
    private var launchedApp: XCUIApplication?

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        launchedApp?.terminate()
        launchedApp = nil
    }

    func testAdHocSignedAppLaunchesOnHostedRunner() throws {
        let app = XCUIApplication()
        launchedApp = app
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
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
        launchedApp = app
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["PLAYSTEAD_WAVE_0_FOCUS_CANARY"] = "1"
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
        var foundStart = false
        for _ in 0..<20 {
            app.typeKey(.tab, modifierFlags: [])
            foundStart = hasKeyboardFocus(expected[0])
            if foundStart { break }
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
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5), "focused canary control did not activate")
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
        // `hasKeyboardFocus` is also reported by accessibility ancestors of
        // the focused control on macOS 26. Restrict the ownership assertion
        // to the actionable role so window/toolbar/group wrappers do not
        // masquerade as additional focus owners.
        let focused = app.buttons
            .matching(NSPredicate(format: "hasKeyboardFocus == true"))
        let focusedLabels = focused.allElementsBoundByIndex.map(\.label)
        XCTAssertEqual(
            focusedLabels.count,
            1,
            "exactly one live button must own keyboard focus; focused=\(focusedLabels)"
        )
        XCTAssertTrue(
            hasKeyboardFocus(expected),
            "unexpected keyboard focus target; focused=\(focusedLabels)"
        )
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
