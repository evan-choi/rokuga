import Foundation

/// Per-frame GPU budget monitor (task 6.2). Tracks a rolling average of composite
/// times and walks down a degradation ladder when the budget is blown. Levels only
/// ever degrade during a recording — no oscillation.
public final class FrameBudgetMonitor: @unchecked Sendable {
    public enum Level: Int, Comparable, Sendable {
        case full = 0
        case noHighlight = 1
        case cursorOnly = 2

        public static func < (lhs: Level, rhs: Level) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    private let budgetSeconds: Double
    private let windowSize: Int
    private let lock = NSLock()
    private var samples: [Double] = []
    private var level: Level = .full

    /// Default budget: 2 ms per frame keeps compositing under 12% of a 60 fps frame interval.
    public init(budgetSeconds: Double = 0.002, windowSize: Int = 60) {
        self.budgetSeconds = budgetSeconds
        self.windowSize = windowSize
    }

    public var currentLevel: Level {
        lock.withLock { level }
    }

    /// Record one frame's composite duration; returns the (possibly degraded) level to use next.
    @discardableResult
    public func record(frameSeconds: Double) -> Level {
        lock.withLock {
            samples.append(frameSeconds)
            guard samples.count >= windowSize else { return level }
            let average = samples.reduce(0, +) / Double(samples.count)
            samples.removeAll(keepingCapacity: true)
            if average > budgetSeconds, let next = Level(rawValue: level.rawValue + 1) {
                level = next
            }
            return level
        }
    }
}
