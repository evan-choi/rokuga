import XCTest
@testable import CaptureKit
import SettingsKit

/// Test double driving the coordinator without any real capture.
final class FakeSession: CaptureSession, @unchecked Sendable {
    let outputURL = URL(fileURLWithPath: "/tmp/fake-recording.mp4")
    private let lock = NSLock()
    private var _started = false
    private var _cancelled = false

    var started: Bool { lock.withLock { _started } }
    var cancelled: Bool { lock.withLock { _cancelled } }

    func start() async throws { lock.withLock { _started = true } }
    func pause() async throws {}
    func resume() async throws {}
    func finish() async throws -> URL { outputURL }
    func cancel() async { lock.withLock { _cancelled = true } }
}

final class RecordingCoordinatorTests: XCTestCase {
    private func makeCoordinator(session: FakeSession = FakeSession()) -> RecordingCoordinator {
        RecordingCoordinator { _ in session }
    }

    func testFullLifecycle() async throws {
        let coordinator = makeCoordinator()
        try await coordinator.start(mode: .fullScreen, countdown: .off)
        var state = await coordinator.state
        XCTAssertEqual(state, .recording)

        try await coordinator.pause()
        state = await coordinator.state
        XCTAssertEqual(state, .paused)

        try await coordinator.resume()
        state = await coordinator.state
        XCTAssertEqual(state, .recording)

        let url = try await coordinator.stop()
        XCTAssertEqual(url.lastPathComponent, "fake-recording.mp4")
        state = await coordinator.state
        XCTAssertEqual(state, .idle)
    }

    func testConcurrentStartIsRejected() async throws {
        let coordinator = makeCoordinator()
        try await coordinator.start(mode: .window, countdown: .off)

        do {
            try await coordinator.start(mode: .window, countdown: .off)
            XCTFail("second start must be rejected")
        } catch let error as RecordingError {
            XCTAssertEqual(error, .alreadyRunning)
        }

        try await coordinator.stop()
    }

    func testStopWhenIdleThrows() async {
        let coordinator = makeCoordinator()
        do {
            try await coordinator.stop()
            XCTFail("stop from idle must throw")
        } catch { /* expected */ }
    }

    func testSessionFailurePropagatesAndResets() async {
        struct Boom: Error {}
        let coordinator = RecordingCoordinator { _ in throw Boom() }
        do {
            try await coordinator.start(mode: .selectedArea, countdown: .off)
            XCTFail("factory failure must propagate")
        } catch { /* expected */ }
        let state = await coordinator.state
        XCTAssertEqual(state, .idle, "must reset to idle so a retry can start")
    }

    func testStateTransitionTable() {
        XCTAssertTrue(RecordingState.idle.canTransition(to: .preparing))
        XCTAssertTrue(RecordingState.preparing.canTransition(to: .recording))
        XCTAssertTrue(RecordingState.recording.canTransition(to: .paused))
        XCTAssertTrue(RecordingState.paused.canTransition(to: .recording))
        XCTAssertTrue(RecordingState.paused.canTransition(to: .finishing))
        XCTAssertTrue(RecordingState.finishing.canTransition(to: .idle))
        XCTAssertTrue(RecordingState.countdown(remaining: 3).canTransition(to: .idle), "Esc cancels countdown")

        XCTAssertFalse(RecordingState.idle.canTransition(to: .recording), "must prepare first")
        XCTAssertFalse(RecordingState.recording.canTransition(to: .idle), "must finalize first")
        XCTAssertFalse(RecordingState.finishing.canTransition(to: .recording))
    }
}
