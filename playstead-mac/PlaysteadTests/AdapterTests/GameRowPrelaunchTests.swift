import XCTest
@testable import Playstead

final class GameRowPrelaunchTests: XCTestCase {
    @MainActor
    func testCancelDropsPendingLaunch() async {
        var launches = 0
        let task = Task { @MainActor in
            try await ControllerChallengeLaunchCoordinator.perform(
                challenge: { try Task.checkCancellation() },
                resumeLaunch: { launches += 1 }
            )
        }
        task.cancel()
        do {
            try await task.value
            XCTFail("cancel should not resume the pending launch")
        } catch is CancellationError { }
        catch { XCTFail("unexpected launch coordinator error: \(error)") }
        XCTAssertEqual(launches, 0)
    }

    @MainActor
    func testFailedAttestationBlocksPendingLaunch() async {
        var launches = 0
        do {
            try await ControllerChallengeLaunchCoordinator.perform(
                challenge: { throw BridgeError.staleAttestation },
                resumeLaunch: { launches += 1 }
            )
            XCTFail("failed attestation must not resume launch")
        } catch { }
        XCTAssertEqual(launches, 0)
    }

    @MainActor
    func testSuccessfulAttestationResumesPendingLaunchOnce() async throws {
        var launches = 0
        try await ControllerChallengeLaunchCoordinator.perform(
            challenge: {},
            resumeLaunch: { launches += 1 }
        )
        XCTAssertEqual(launches, 1)
    }

    @MainActor
    func testSameSessionPlayReusesValidAttestation() async throws {
        let session = ControllerAttestationSession()
        let proof = ControllerAttestation(
            controllerID: "assigned-runtime-test", instanceID: 41, guid: "private-test-guid",
            generation: 7, bindings: ["buttonA": .button(0)]
        )
        let device = SDLDeviceSnapshot(
            instanceID: 41, guid: "private-test-guid", name: "Synthetic SDL Device",
            bindings: ["buttonA": .button(0)]
        )
        var challenges = 0
        var launches = 0

        for _ in 0..<2 {
            try await ControllerChallengeLaunchCoordinator.perform(
                challenge: {
                    _ = try await session.attestation {
                        challenges += 1
                        return (proof, device)
                    }
                },
                resumeLaunch: { launches += 1 }
            )
        }
        XCTAssertEqual(challenges, 1)
        XCTAssertEqual(launches, 2, "each Play request resumes once while reusing its session proof")
    }
}
