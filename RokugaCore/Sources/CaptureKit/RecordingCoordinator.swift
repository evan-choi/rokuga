import Foundation
import SettingsKit

/// Abstraction over the concrete capture backend (SCStream in production, fakes in tests).
/// Implemented in 2.2+.
public protocol CaptureSession: Sendable {
    func start() async throws
    func pause() async throws
    func resume() async throws
    /// Stops capture and finalizes the output file, returning its URL.
    func finish() async throws -> URL
    /// Aborts without finalizing (pre-recording cancel).
    func cancel() async
}

/// Events published to the UI layer.
public enum RecordingEvent: Equatable, Sendable {
    case stateChanged(RecordingState)
    case countdownTick(remaining: Int)
    case finished(outputURL: URL)
    case failed(RecordingError)
}

/// Owns the recording state machine.
/// All lifecycle mutations flow through this actor, giving single-flight semantics for free: concurrent `start()` calls are serialized, and the state check
/// rejects the loser.
public actor RecordingCoordinator {
    public private(set) var state: RecordingState = .idle

    private var session: CaptureSession?
    private let makeSession: @Sendable (RecordingMode) async throws -> CaptureSession
    private var eventContinuations: [UUID: AsyncStream<RecordingEvent>.Continuation] = [:]
    private var countdownTask: Task<Void, Never>?

    public init(makeSession: @escaping @Sendable (RecordingMode) async throws -> CaptureSession) {
        self.makeSession = makeSession
    }

    // MARK: Event stream

    /// Subscribe to lifecycle events. Multiple subscribers supported.
    public func events() -> AsyncStream<RecordingEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            eventContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
    }

    private func removeContinuation(_ id: UUID) {
        eventContinuations[id] = nil
    }

    private func emit(_ event: RecordingEvent) {
        for continuation in eventContinuations.values {
            continuation.yield(event)
        }
    }

    // MARK: Transitions

    private func transition(to next: RecordingState) throws {
        guard state.canTransition(to: next) else {
            throw RecordingError.invalidTransition(from: "\(state)", to: "\(next)")
        }
        state = next
        emit(.stateChanged(next))
    }

    // MARK: Lifecycle

    /// Start a recording. Rejects if any session is already in flight.
    public func start(mode: RecordingMode, countdown: CountdownDuration) async throws {
        guard state.canStart else { throw RecordingError.alreadyRunning }
        try transition(to: .preparing)

        do {
            let session = try await makeSession(mode)
            self.session = session

            if countdown != .off {
                try await runCountdown(seconds: countdown.rawValue)
                // Countdown may have been cancelled → state returned to idle.
                guard state == .countdown(remaining: 0) else { return }
            }

            try transition(to: .recording)
            try await session.start()
        } catch {
            await abortToIdle(with: error)
            throw error
        }
    }

    public func pause() async throws {
        guard let session, state == .recording else { return }
        try transition(to: .paused)
        try await session.pause()
    }

    public func resume() async throws {
        guard let session, state == .paused else { return }
        try transition(to: .recording)
        try await session.resume()
    }

    /// Stop and finalize. Returns the output URL.
    @discardableResult
    public func stop() async throws -> URL {
        guard let session, state == .recording || state == .paused else {
            throw RecordingError.invalidTransition(from: "\(state)", to: "finishing")
        }
        try transition(to: .finishing)
        do {
            let url = try await session.finish()
            self.session = nil
            try transition(to: .idle)
            emit(.finished(outputURL: url))
            return url
        } catch {
            await abortToIdle(with: error)
            throw error
        }
    }

    /// Abort the in-flight session without producing a file. The app only calls this
    /// for Esc during preparation/countdown; non-UI clients may also abort recording.
    public func cancel() async {
        countdownTask?.cancel()
        countdownTask = nil
        switch state {
        case .preparing, .countdown, .recording, .paused:
            await session?.cancel()
            session = nil
            state = .idle
            emit(.stateChanged(.idle))
        default:
            break
        }
    }

    /// Source disconnect (display unplug, window closed) — finalize what was captured so far instead of losing it (task 2.5).
    public func handleSessionInterruption() async {
        guard state == .recording || state == .paused, let session else { return }
        emit(.failed(.captureSourceLost))
        try? transition(to: .finishing)
        if let url = try? await session.finish() {
            emit(.finished(outputURL: url))
        }
        self.session = nil
        state = .idle
        emit(.stateChanged(.idle))
    }

    // MARK: Countdown

    private func runCountdown(seconds: Int) async throws {
        for remaining in stride(from: seconds, through: 1, by: -1) {
            try transition(to: .countdown(remaining: remaining))
            emit(.countdownTick(remaining: remaining))
            try await Task.sleep(nanoseconds: 1_000_000_000)
            if state == .idle {
                return
            } // cancelled mid-countdown
        }
        try transition(to: .countdown(remaining: 0))
    }

    // MARK: Failure path

    private func abortToIdle(with error: Error) async {
        await session?.cancel()
        session = nil
        let recordingError = error as? RecordingError ?? .encoderFailure("\(error)")
        state = .idle
        emit(.failed(recordingError))
        emit(.stateChanged(.idle))
    }
}
