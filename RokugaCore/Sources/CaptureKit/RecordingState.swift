import Foundation

/// Recording lifecycle states (see design.md — RecordingCoordinator).
///
/// idle → preparing → countdown → recording ⇄ paused → finishing → idle
/// Any pre-recording state can abort back to idle.
public enum RecordingState: Equatable, Sendable {
    case idle
    case preparing
    case countdown(remaining: Int)
    case recording
    case paused
    case finishing

    /// Whether a start request is currently allowed (single-flight guarantee).
    public var canStart: Bool {
        self == .idle
    }

    /// Whether the session is actively producing or holding frames.
    public var isActive: Bool {
        switch self {
        case .recording, .paused, .finishing: true
        case .idle, .preparing, .countdown: false
        }
    }

    /// Valid transitions of the state machine. Everything else is a logic error.
    public func canTransition(to next: RecordingState) -> Bool {
        switch (self, next) {
        case (.idle, .preparing),
             (.preparing, .countdown),
             (.preparing, .recording), // countdown = off
             (.countdown, .countdown), // tick
             (.countdown, .recording),
             (.recording, .paused),
             (.paused, .recording),
             (.recording, .finishing),
             (.paused, .finishing),
             (.finishing, .idle):
            true
        // Aborts: anything not yet finalizing can cancel to idle.
        case (.preparing, .idle), (.countdown, .idle):
            true
        default:
            false
        }
    }
}

/// Errors surfaced by the recording pipeline.
public enum RecordingError: Error, Equatable, Sendable {
    case alreadyRunning
    case invalidTransition(from: String, to: String)
    case permissionDenied
    case diskFull(freeBytes: Int64)
    case captureSourceLost
    case encoderFailure(String)
}
