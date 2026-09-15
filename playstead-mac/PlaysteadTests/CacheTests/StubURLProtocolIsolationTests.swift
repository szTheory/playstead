import XCTest
@testable import Playstead

/// Pins WINDOWS #70's fix, and pins the constraint that makes the obvious
/// version of that fix wrong.
///
/// The defect: `StubURLProtocol.requestLog` is process-global, and
/// `reset()`'s `inFlightGroup.wait()` only covers a response already being
/// delivered. A `URLSessionTask` from an earlier test that had not yet
/// issued its request appended into the NEXT test's log, which is how
/// `RelaunchTests`' "the relaunch path must make zero network requests"
/// failed for a request it never made.
///
/// The constraint: `reset()` is also called mid-test, so retiring every
/// live session on `reset()` would break the suites that do that. Both
/// facts are asserted here, because a fix that satisfies only the first is
/// the one #70 explicitly warns against.
final class StubURLProtocolIsolationTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        StubURLProtocol.reset()
    }

    override func tearDownWithError() throws {
        StubURLProtocol.reset()
        try super.tearDownWithError()
    }

    private func get(_ session: URLSession) async -> (Data, URLResponse)? {
        try? await session.data(from: URL(string: "https://stub.test/probe")!)
    }

    /// The failing half: a session left over from a finished test must not
    /// reach the next test's log. Two `reset()` calls stand in for that
    /// test boundary — one ends the owning test, one begins the next.
    func test_aSessionRetiredByTwoResetsCannotAppendToTheNextTestsLog() async throws {
        let stale = StubURLProtocol.makeSession()
        StubURLProtocol.responder = { _ in
            StubURLProtocol.Stub(statusCode: 200, headers: [:], body: Data("late".utf8))
        }

        StubURLProtocol.reset()  // the owning test ends
        StubURLProtocol.reset()  // the next test begins

        StubURLProtocol.responder = { _ in
            StubURLProtocol.Stub(statusCode: 200, headers: [:], body: Data("current".utf8))
        }

        let result = await get(stale)

        // One clause per fact: CI keeps file:line and drops assertion text.
        XCTAssertNil(result, "a retired session's request must not be served")
        XCTAssertTrue(
            StubURLProtocol.requestLog.isEmpty,
            "a retired session's request must never appear in the next test's log"
        )
    }

    /// The constraint half: `SaveConflictResolverTests` calls
    /// `makeSession()` and then `reset()` inside `setUp`, and `FilterTests`
    /// resets partway through a test. A session must therefore survive one
    /// `reset()` and still work.
    func test_aSessionSurvivesTheMidTestResetItsOwnSuitePerforms() async throws {
        let session = StubURLProtocol.makeSession()

        StubURLProtocol.reset()  // mid-test, exactly as those suites do

        StubURLProtocol.responder = { _ in
            StubURLProtocol.Stub(statusCode: 200, headers: [:], body: Data("served".utf8))
        }

        let result = await get(session)

        XCTAssertEqual(result?.0, Data("served".utf8), "a mid-test reset must not cancel the running test's own session")
        XCTAssertEqual(StubURLProtocol.requestLog.count, 1, "that request belongs in the log")
    }
}
