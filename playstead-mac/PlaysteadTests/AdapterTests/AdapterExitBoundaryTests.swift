import XCTest
@testable import Playstead

/// SEED-034 item 1, and the gate that would have caught WINDOWS #76 on day
/// one.
///
/// `AdapterPinTests.testExitDetectionClassifiesAllThreeKnownSignatures`
/// decodes its own fixture and then asserts the classification that
/// fixture describes — a closed loop that is green no matter what the
/// shipped pin says. It stayed green for the whole of phase 03 while the
/// most common real exit in the product, the user quitting the emulator,
/// classified as `.unknown`.
///
/// This suite breaks the loop in both directions:
///
///   1. It classifies against `AdapterPin.load()` — the pin that actually
///      ships in the bundle — never a literal written next to the
///      assertion.
///   2. It gets its `(terminationStatus, terminationReason)` pairs from
///      **real child processes** that really exit and really die to
///      signals, rather than from integers typed into the test. No
///      emulator and no ROM is needed for that: `/bin/sleep` exits
///      `0 / exit` exactly as mGBA does, and a shell that signals itself
///      produces exactly the signatures a crashing or killed emulator
///      produces.
final class AdapterExitBoundaryTests: XCTestCase {
    /// Runs `command` to completion and returns what `Process` actually
    /// observed — the same two values `AdapterHost` hands to `classify`.
    private func realTermination(
        _ command: String, file: StaticString = #filePath, line: UInt = #line
    ) throws -> (status: Int32, reason: Process.TerminationReason) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return (process.terminationStatus, process.terminationReason)
    }

    private func pin() throws -> AdapterExitDetection {
        try AdapterPin.load().exitDetection
    }

    // MARK: - The boundary sweep

    /// Every combination of {0, 9, 11, 15} x {exit, uncaughtSignal} that a
    /// child process can actually produce must land in a *named* case.
    ///
    /// `.unknown` is the pin failing to describe reality, and the product
    /// consequence is not cosmetic: it is what "Last exit: unknown(status:
    /// 0, reason: \"exit\")" said to the owner after a perfectly normal
    /// quit, and what any future save-recovery decision would have had to
    /// act on.
    func testNoRealChildProcessTerminationClassifiesAsUnknown() throws {
        let detection = try pin()
        let cases: [(label: String, command: String)] = [
            ("normal exit", "exit 0"),
            ("SIGKILL", "kill -9 $$; sleep 5"),
            ("SIGSEGV", "kill -11 $$; sleep 5"),
            ("SIGTERM", "kill -15 $$; sleep 5"),
        ]

        for scenario in cases {
            try XCTContext.runActivity(named: scenario.label) { _ in
                let termination = try realTermination(scenario.command)
                let classification = AdapterExit.classify(
                    status: termination.status, reason: termination.reason, against: detection
                )
                if case .unknown(let status, let reason) = classification {
                    XCTFail(
                        "\(scenario.label) produced status \(status) / \(reason), which the shipped pin does not describe"
                    )
                }
            }
        }
    }

    /// The sweep above would be satisfied by a pin that called everything
    /// `clean`, so each signature is also pinned to its meaning.
    func testEachRealTerminationClassifiesAsTheRightNamedCase() throws {
        let detection = try pin()
        let expectations: [(label: String, command: String, expected: AdapterExit)] = [
            ("the user quit the emulator", "exit 0", .clean),
            ("the process was killed outright", "kill -9 $$; sleep 5", .killed),
            ("the process crashed", "kill -11 $$; sleep 5", .crashed),
            // What `AdapterHost.terminateAll()` itself sends. Not `.clean`:
            // the pin's own recorded evidence is that mGBA dies to SIGTERM
            // exactly like a crash, with no save-and-quit (WINDOWS #76).
            ("Playstead asked the process to stop", "kill -15 $$; sleep 5", .killed),
        ]

        for expectation in expectations {
            try XCTContext.runActivity(named: expectation.label) { _ in
                let termination = try realTermination(expectation.command)
                XCTAssertEqual(
                    AdapterExit.classify(
                        status: termination.status, reason: termination.reason, against: detection
                    ),
                    expectation.expected,
                    expectation.label
                )
            }
        }
    }

    /// The single fact the owner hit by hand, stated on its own so a
    /// regression names itself in one line.
    func testAnOrdinaryQuitOfTheShippedEmulatorIsClean() throws {
        let termination = try realTermination("exit 0")
        XCTAssertEqual(termination.status, 0)
        XCTAssertEqual(termination.reason, .exit)
        XCTAssertEqual(AdapterExit.classify(status: 0, reason: .exit, against: try pin()), .clean)
    }

    /// A signature genuinely outside the pin must still surface as
    /// `.unknown` — the sweep must not be passing because `.unknown`
    /// became unreachable.
    func testAnUndescribedTerminationStillSurfacesAsUnknown() throws {
        let termination = try realTermination("exit 42")
        XCTAssertEqual(
            AdapterExit.classify(status: termination.status, reason: termination.reason, against: try pin()),
            .unknown(status: 42, reason: "exit")
        )
    }

    // MARK: - The pin's shape

    /// A category holding several signatures is the whole mechanism this
    /// fix rests on; asserted against the shipped pin so a future edit
    /// that collapses it back to one is caught here rather than by a user.
    func testShippedPinDescribesBothWaysPlaysteadEndsAProcess() throws {
        let detection = try pin()
        let killedPairs = Set(detection.killed.map { "\($0.terminationStatus)/\($0.terminationReason)" })
        XCTAssertEqual(killedPairs, ["9/uncaughtSignal", "15/uncaughtSignal"])
        XCTAssertEqual(detection.clean.map(\.terminationStatus), [0])
        XCTAssertEqual(detection.crash.map(\.terminationStatus), [11])
    }

    /// The older single-signature shape must keep decoding: several test
    /// fixtures still use it, and so would any pin written before this
    /// change.
    func testASingleSignatureCategoryStillDecodes() throws {
        let json = """
        {"clean": {"terminationStatus": 0, "terminationReason": "exit"},
         "crash": {"terminationStatus": 11, "terminationReason": "uncaughtSignal"},
         "killed": {"terminationStatus": 9, "terminationReason": "uncaughtSignal"}}
        """
        let detection = try JSONDecoder().decode(AdapterExitDetection.self, from: Data(json.utf8))
        XCTAssertEqual(detection.clean.count, 1)
        XCTAssertEqual(AdapterExit.classify(status: 0, reason: .exit, against: detection), .clean)
    }
}
