#if UI_TESTING
import Foundation

@MainActor
final class UITestProfileSession {
    let fixture: DeterministicProfileFixture
    let environment: AppEnvironment

    init(fixture: DeterministicProfileFixture, environment: AppEnvironment) {
        self.fixture = fixture
        self.environment = environment
    }

    deinit {
        try? fixture.cleanup()
    }
}

/// Fail-closed bridge from the process environment to one finite profile.
/// The selector is a name only; no root, SQL, JSON, or fixture bytes are accepted.
enum UITestBootstrap {
    static let modeKey = "PLAYSTEAD_UI_TESTING"
    static let profileKey = "PLAYSTEAD_UI_TEST_PROFILE"

    static func isRequested(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment[modeKey] == "1"
    }

    @MainActor
    static func makeSession(
        environment processEnvironment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> UITestProfileSession {
        guard isRequested(environment: processEnvironment) else {
            throw DeterministicProfileError.missingProfile
        }
        let profile = try DeterministicProfile.parse(processEnvironment[profileKey])
        let fixture = try profile.makeFixture()
        let appEnvironment = AppEnvironment(
            uiTestingPaths: fixture.paths,
            localStore: fixture.localStore,
            reachability: Reachability(startOnline: false, monitorAutomatically: false)
        )
        appEnvironment.blockExternalIOForUITesting()
        try fixture.assertExactState()
        return UITestProfileSession(fixture: fixture, environment: appEnvironment)
    }
}
#endif
